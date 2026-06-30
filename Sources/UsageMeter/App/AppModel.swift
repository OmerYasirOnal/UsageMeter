import Foundation
import Combine
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

    /// Source A bridge (login cookies + discovered endpoint). Observed by the UI.
    let accountAuth: AccountAuth

    private let engine: DataEngine
    private let notifier = UsageNotifier()
    private var autoRefreshTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()
    private var didFinishInit = false

    init() {
        let loaded = AppSettings.load()
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
        self.engine = DataEngine(
            configuration: loaded.engineConfiguration,
            accountClient: accountClient
        )

        var initial = loaded
        if LaunchAtLogin.isAvailable {
            initial.launchAtLogin = LaunchAtLogin.isEnabled
        }
        self.settings = initial

        didFinishInit = true

        if initial.notificationsEnabled {
            notifier.requestAuthorizationIfNeeded()
        }

        // Refresh when the login capture discovers an endpoint or captures usage.
        auth.$endpointInfo.dropFirst()
            .sink { [weak self] _ in Task { await self?.refresh() } }
            .store(in: &cancellables)
        auth.$lastCaptured.dropFirst()
            .sink { [weak self] _ in Task { await self?.refresh() } }
            .store(in: &cancellables)

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
        if DemoData.isEnabled { snapshot = DemoData.snapshot(); hasLoadedOnce = true; return }
        guard !isRefreshing else { return }
        isRefreshing = true
        snapshot = await engine.refreshAll()
        hasLoadedOnce = true
        isRefreshing = false
        notifier.evaluate(snapshot.account, enabled: settings.notificationsEnabled)
    }

    func logOut() async {
        await accountAuth.logout()
        notifier.reset()
        // Clear immediately so the UI can't show stale % even if a refresh is
        // coalesced away by the isRefreshing guard.
        var snap = snapshot
        snap.account = nil
        snapshot = snap
        await refresh()
    }

    // MARK: - Settings application

    private func applySettings(previous: AppSettings) {
        guard didFinishInit else { return }
        settings.save()

        let newConfig = settings.engineConfiguration
        let rootsChanged = newConfig.projectRoots != previous.engineConfiguration.projectRoots
        let intervalChanged = settings.refreshIntervalMinutes != previous.refreshIntervalMinutes

        if newConfig != previous.engineConfiguration {
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
    }
}
