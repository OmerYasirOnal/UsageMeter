import Foundation

/// The data engine: an actor that orchestrates the three decoupled sources off
/// the main thread. The UI talks to it via async calls and renders the returned
/// `EngineSnapshot`.
///
/// Decoupling guarantee: a failure in any one source never breaks the others.
///   • Source B (`ClaudeCodeSource`) — always available, no auth.
///   • Source C (`StatusClient`) — failure keeps the last good status.
///   • Source A (`AccountUsageClient`) — `nil`/throw → local-only mode; B and C
///     still render.
public actor DataEngine {
    private var configuration: EngineConfiguration

    private let claudeCode: ClaudeCodeSource
    private let statusClient: any StatusClient
    private let accountClient: any AccountUsageClient
    private let statusStore: StatusStore

    /// Last good status (Source C), seeded from disk so launch shows it instantly.
    private var lastStatus: ServiceStatus?

    /// Account (Source A) politeness throttle: the unofficial claude.ai endpoint is
    /// hit at most once per `accountFloor`, no matter how many callers fire
    /// (background loop, popover, wake, network reconnect, manual button). Between
    /// hits, the last good value is served — carrying its real `fetchedAt` so the UI
    /// can show how old it is.
    private var lastAccountFetchAt: Date?
    private var lastAccount: AccountUsage?
    private static let accountFloor: TimeInterval = 60
    /// How long a last-good account value may be served after a FAILED fetch
    /// before degrading to local-only. Bounded so a dead session (401 → nil)
    /// can't show stale numbers forever, while a transient blip (offline, 5xx,
    /// decode hiccup) doesn't blank the UI and reset burn baselines.
    private static let accountStaleTTL: TimeInterval = 30 * 60

    public init(
        configuration: EngineConfiguration = EngineConfiguration(),
        recordStore: UsageStore = UsageStore(),
        statusStore: StatusStore = StatusStore(),
        statusClient: any StatusClient = LiveStatusClient(),
        accountClient: any AccountUsageClient = LocalOnlyAccountUsageClient(),
        pricing: Pricing = .loadFromMainBundle(),
        calendar: Calendar = .current,
        claudeCodeSource: ClaudeCodeSource? = nil
    ) {
        self.configuration = configuration
        self.statusStore = statusStore
        self.statusClient = statusClient
        self.accountClient = accountClient
        self.claudeCode = claudeCodeSource
            ?? LocalClaudeCodeSource(store: recordStore, pricing: pricing, calendar: calendar)
        self.lastStatus = statusStore.load()
    }

    public var currentConfiguration: EngineConfiguration { configuration }

    public func updateConfiguration(_ newValue: EngineConfiguration) {
        configuration = newValue
    }

    /// Immediate snapshot from caches (cheap; no scan or network). Call on launch
    /// so the menu bar shows last-known values instantly.
    public func cachedSnapshot() -> EngineSnapshot {
        let stats = claudeCode.cachedStats(now: Date())
        return EngineSnapshot(
            claudeCode: stats,
            status: lastStatus,
            account: nil,
            lastUpdated: claudeCode.lastUpdated
        )
    }

    /// Incrementally rescan Source B.
    public func refreshClaudeCode() -> ClaudeCodeStats {
        claudeCode.refresh(roots: configuration.projectRoots, now: Date())
    }

    /// Refresh Source C. On failure, keep (and return) the last good status.
    @discardableResult
    public func refreshStatus() async -> ServiceStatus? {
        do {
            let status = try await statusClient.fetch()
            lastStatus = status
            statusStore.save(status)
            return status
        } catch {
            return lastStatus
        }
    }

    /// Refresh Source A. `nil` → local-only mode (never throws to the caller).
    /// Floor-guarded: within `accountFloor` of the last successful fetch it returns
    /// the cached value without touching the network, so any number of event
    /// triggers stays polite (≤ 1 endpoint hit per minute). On a failed fetch the
    /// last good value is served for up to `accountStaleTTL` — carrying its real
    /// `fetchedAt` so the UI can show how old it is — and the floor is NOT
    /// stamped, so the next trigger retries immediately.
    public func refreshAccount(now: Date = Date()) async -> AccountUsage? {
        if let last = lastAccountFetchAt, now.timeIntervalSince(last) < Self.accountFloor {
            return lastAccount
        }
        let fetched = (try? await accountClient.currentUsage()) ?? nil
        guard var usage = fetched else {
            if let lastGood = lastAccount, let fetchedAt = lastGood.fetchedAt,
               now.timeIntervalSince(fetchedAt) < Self.accountStaleTTL {
                return lastGood
            }
            lastAccount = nil
            return nil
        }
        usage.fetchedAt = now             // real fetch time → honest freshness in the UI
        lastAccount = usage
        lastAccountFetchAt = now
        return usage
    }

    /// Full refresh of all sources, returning a unified snapshot. Source C and A
    /// run concurrently; Source B is local/fast and runs inline.
    public func refreshAll() async -> EngineSnapshot {
        async let statusTask = refreshStatus()
        async let accountTask = refreshAccount()
        let stats = refreshClaudeCode()
        // Capture synchronously BEFORE suspending so actor reentrancy during the
        // awaits cannot make the returned snapshot internally inconsistent.
        let updated = claudeCode.lastUpdated
        let status = await statusTask
        let account = await accountTask
        return EngineSnapshot(
            claudeCode: stats,
            status: status,
            account: account,
            lastUpdated: updated
        )
    }

    /// Drop the account (Source A) throttle cache so the next refresh fetches
    /// immediately. Call on logout so a stale account can't be served during the
    /// 60s window, and so re-login shows fresh numbers at once.
    public func clearAccountCache() {
        lastAccount = nil
        lastAccountFetchAt = nil
    }

    /// Clear all cached state.
    public func resetCache() {
        claudeCode.reset()
        statusStore.clear()
        lastStatus = nil
        clearAccountCache()
    }
}
