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
    public func refreshAccount() async -> AccountUsage? {
        (try? await accountClient.currentUsage()) ?? nil
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

    /// Clear all cached state.
    public func resetCache() {
        claudeCode.reset()
        statusStore.clear()
        lastStatus = nil
    }
}
