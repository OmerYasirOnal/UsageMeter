import Foundation
import Combine
import AppKit
import Network
import UsageMeterKit

/// The single source of truth for the UI. Lives on the main actor, owns the
/// `DataEngine` actor and the `AccountAuth` bridge, and republishes immutable
/// snapshots.
@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var snapshot: EngineSnapshot = .empty
    @Published private(set) var isRefreshing = false
    @Published private(set) var hasLoadedOnce = false
    @Published var settings: AppSettings {
        didSet { applySettings(previous: oldValue) }
    }

    #if !APPSTORE
    /// Source A bridge (login cookies + discovered endpoint). Observed by the UI.
    /// Compiled out of the local-only App Store build (no claude.ai login).
    let accountAuth: AccountAuth
    #endif

    private let engine: DataEngine
    private let notifier = UsageNotifier()
    private var autoRefreshTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()
    private var didFinishInit = false
    /// Coalescing flag: a refresh requested while one is in flight runs exactly once
    /// more when it finishes (never silently dropped, never a queue).
    private var pendingRefresh = false
    /// Network reachability: refresh on the offline→online edge (floor-guarded).
    private let pathMonitor = NWPathMonitor()
    private var lastPathSatisfied = true
    /// First observation seen this reset-cycle per metric, for the burn projection
    /// ("when will you run out"). In-memory: re-gathers ~15 min after a relaunch.
    private var cycleObs: [String: (cycleKey: String, pct: Double, date: Date)] = [:]

    init() {
        ClaudeFolderAccess.restore()   // sandbox: reopen a previously-granted ~/.claude
        let loaded = AppSettings.load()

        #if APPSTORE
        // Local-only App Store build: no claude.ai login / unofficial endpoint
        // (Source B + C only). Clean App Review, "100% private, no account needed".
        let accountClient: any AccountUsageClient = LocalOnlyAccountUsageClient()
        #else
        let auth = AccountAuth()
        self.accountAuth = auth
        // The live account client: captured-value fallback + auth reconciliation
        // are routed THROUGH the client so Source A stays behind the protocol.
        let accountClient = LiveAccountUsageClient(
            session: auth,
            endpoint: auth,
            captured: auth,
            onAuthResult: { [weak auth] ok in
                Task { @MainActor in auth?.setAuthenticated(ok) }
            }
        )
        #endif
        self.engine = DataEngine(
            configuration: Self.mergedConfig(for: loaded),
            accountClient: accountClient
        )

        var initial = loaded
        if LaunchAtLogin.isAvailable {
            initial.launchAtLogin = LaunchAtLogin.isEnabled
        }
        self.settings = initial

        // Demo: populate synchronously so the UI (and screenshot renderer) has data immediately.
        if DemoData.isEnabled {
            self.snapshot = DemoData.snapshot()
            self.hasLoadedOnce = true
        }

        didFinishInit = true

        if initial.notificationsEnabled {
            notifier.requestAuthorizationIfNeeded()
        }

        #if !APPSTORE
        // Refresh when the login capture discovers an endpoint or captures usage.
        auth.$endpointInfo.dropFirst()
            .sink { [weak self] _ in Task { await self?.refresh() } }
            .store(in: &cancellables)
        auth.$lastCaptured.dropFirst()
            .sink { [weak self] _ in Task { await self?.refresh() } }
            .store(in: &cancellables)
        #endif

        // The Mac's data goes stale while it sleeps — refresh as soon as it wakes
        // so the popover is current the moment the user looks (event-driven, not polling).
        NSWorkspace.shared.notificationCenter
            .publisher(for: NSWorkspace.didWakeNotification)
            .sink { [weak self] _ in Task { await self?.refresh() } }
            .store(in: &cancellables)

        // Refresh the instant the network comes back (offline→online edge only).
        // The engine's 60s floor keeps this polite regardless of flapping.
        pathMonitor.pathUpdateHandler = { [weak self] path in
            let satisfied = (path.status == .satisfied)
            Task { @MainActor [weak self] in
                guard let self else { return }
                let cameOnline = satisfied && !self.lastPathSatisfied
                self.lastPathSatisfied = satisfied
                if cameOnline { await self.refresh() }
            }
        }
        pathMonitor.start(queue: DispatchQueue(label: "com.usagemeter.network-monitor"))

        Task { await bootstrap() }
    }

    /// Show cached values instantly, then do a live refresh and start the timer.
    func bootstrap() async {
        if DemoData.isEnabled { snapshot = DemoData.snapshot(); hasLoadedOnce = true; return }
        snapshot = await engine.cachedSnapshot()
        hasLoadedOnce = true
        await refresh()
        startAutoRefresh()
    }

    /// On-demand full refresh (also called when the popover opens / after login).
    func refresh() async {
        if DemoData.isEnabled {
            snapshot = DemoData.snapshot(); hasLoadedOnce = true
            updateCycleObservations(snapshot.account)
            return
        }
        // Coalesce: if a refresh is already running, mark one trailing re-run and
        // return — so the freshness-critical triggers (popover open, after login,
        // wake, reconnect, manual) are never silently dropped by a busy guard.
        if isRefreshing { pendingRefresh = true; return }
        isRefreshing = true
        repeat {
            pendingRefresh = false
            snapshot = await engine.refreshAll()
            hasLoadedOnce = true
            updateCycleObservations(snapshot.account)
            notifier.evaluate(snapshot.account, enabled: settings.notificationsEnabled)
        } while pendingRefresh
        isRefreshing = false
    }

    // MARK: - Burn projection ("when will you run out")

    /// Record the first % seen in the current reset-cycle for each metric, so the
    /// projection has a smoothed baseline. Keeps the earliest sample per cycle.
    private func updateCycleObservations(_ account: AccountUsage?, now: Date = Date()) {
        let metrics: [(String, UsageMetric?)] = [
            ("Session", account?.session), ("Weekly", account?.weekly), ("Weekly Opus", account?.weeklyOpus)
        ]
        for (name, metric) in metrics {
            guard let metric else { cycleObs[name] = nil; continue }
            let key = NotificationPolicy.cycleKey(for: metric.resetsAt)
            if DemoData.isEnabled {
                // Seed a synthetic baseline so the demo shows a live projection now
                // (real mode gathers ~15 min of real observation first).
                cycleObs[name] = (key, max(0, metric.percent - 14), now.addingTimeInterval(-90 * 60))
                continue
            }
            if cycleObs[name]?.cycleKey != key {
                cycleObs[name] = (key, metric.percent, now)   // new cycle → new baseline
            }
        }
    }

    /// The burn projection for a named account metric at `now` — drive from a
    /// `TimelineView` so the "time to limit" ticks down live.
    func projection(for name: String, _ metric: UsageMetric, now: Date = Date()) -> UsageProjection {
        let obs = cycleObs[name]
        return UsageProjection.compute(
            percent: metric.percent, resetsAt: metric.resetsAt,
            startPercent: obs?.pct, startDate: obs?.date, now: now)
    }

    /// Prompt for sandbox access to `~/.claude`, then reconfigure + refresh.
    func grantClaudeFolderAccess() async {
        guard ClaudeFolderAccess.requestAccess() else { return }
        await engine.updateConfiguration(Self.mergedConfig(for: settings))
        await refresh()
    }

    /// Engine roots = the security-scoped grant (if any) + the user's configured /
    /// default roots, de-duplicated.
    @MainActor
    private static func mergedConfig(for settings: AppSettings) -> EngineConfiguration {
        var roots = ClaudeFolderAccess.scanRoots()
        roots.append(contentsOf: settings.engineConfiguration.projectRoots)
        var seen = Set<String>()
        roots = roots.filter { seen.insert($0.standardizedFileURL.path).inserted }
        return EngineConfiguration(projectRoots: roots,
                                   refreshInterval: settings.engineConfiguration.refreshInterval)
    }

    #if !APPSTORE
    func logOut() async {
        await accountAuth.logout()
        await engine.clearAccountCache()   // don't let the 60s throttle serve the old account
        notifier.reset()
        // Clear immediately so the UI can't show stale % even if a refresh is
        // coalesced away by the isRefreshing guard.
        var snap = snapshot
        snap.account = nil
        snapshot = snap
        await refresh()
    }
    #endif

    // MARK: - Settings application

    private func applySettings(previous: AppSettings) {
        guard didFinishInit else { return }
        settings.save()

        let newConfig = Self.mergedConfig(for: settings)
        let previousConfig = Self.mergedConfig(for: previous)
        let rootsChanged = newConfig.projectRoots != previousConfig.projectRoots
        let intervalChanged = settings.refreshIntervalMinutes != previous.refreshIntervalMinutes

        if newConfig != previousConfig {
            Task { await engine.updateConfiguration(newConfig) }
        }
        if rootsChanged {
            Task { await refresh() }
        }
        if intervalChanged {
            startAutoRefresh()
        }
        if settings.launchAtLogin != previous.launchAtLogin {
            let ok = LaunchAtLogin.setEnabled(settings.launchAtLogin)
            if !ok && settings.launchAtLogin {
                settings.launchAtLogin = false
            }
        }
        if settings.notificationsEnabled && !previous.notificationsEnabled {
            notifier.requestAuthorizationIfNeeded()
        }
    }

    // MARK: - Auto refresh (adaptive, polite)

    private func startAutoRefresh() {
        autoRefreshTask?.cancel()
        autoRefreshTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { break }
                let base = self.settings.engineConfiguration.refreshInterval
                let interval = AccountRefreshPolicy.interval(for: self.snapshot.account, base: base)
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
                if Task.isCancelled { break }
                await self.refresh()
            }
        }
    }

    deinit {
        autoRefreshTask?.cancel()
        pathMonitor.cancel()
    }
}
