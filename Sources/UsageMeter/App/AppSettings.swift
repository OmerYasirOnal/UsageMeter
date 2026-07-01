import Foundation
import UsageMeterKit

/// User-facing settings, persisted in `UserDefaults`.
struct AppSettings: Equatable {
    /// Override scan roots. Empty → use `ProjectScanner.defaultRoots()`.
    var projectRootPaths: [String]
    /// Refresh cadence in minutes (clamped to a polite minimum).
    var refreshIntervalMinutes: Double
    var launchAtLogin: Bool
    /// Show today's estimated cost next to the menu-bar icon.
    var showCostInMenuBar: Bool
    /// Show the account session % as the menu-bar title (Source A, when logged in).
    var showPercentInMenuBar: Bool
    /// Show the Claude Code "API value" estimate (what local tokens would cost on
    /// the pay-as-you-go API). This is NOT your real spend on a subscription.
    var showApiValue: Bool
    /// Notify at 50/75/90% and when on track to hit a limit before reset.
    var notificationsEnabled: Bool
    /// Color-scheme override.
    var appearance: AppAppearance

    static let `default` = AppSettings(
        projectRootPaths: [],
        refreshIntervalMinutes: 1,
        launchAtLogin: false,
        showCostInMenuBar: false,
        showPercentInMenuBar: true,
        showApiValue: true,
        notificationsEnabled: true,
        appearance: .system
    )

    /// Minimum polite refresh interval (seconds) regardless of the chosen minutes.
    static let minimumIntervalSeconds: TimeInterval = 60

    var engineConfiguration: EngineConfiguration {
        let roots: [URL]
        if projectRootPaths.isEmpty {
            roots = ProjectScanner.defaultRoots()
        } else {
            roots = projectRootPaths.map {
                URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath, isDirectory: true)
            }
        }
        let interval = max(Self.minimumIntervalSeconds, refreshIntervalMinutes * 60)
        return EngineConfiguration(projectRoots: roots, refreshInterval: interval)
    }

    // MARK: - Persistence

    private enum Keys {
        static let projectRoots = "settings.projectRootPaths"
        static let refreshMinutes = "settings.refreshIntervalMinutes"
        static let launchAtLogin = "settings.launchAtLogin"
        static let showCost = "settings.showCostInMenuBar"
        static let showPercent = "settings.showPercentInMenuBar"
        static let showApiValue = "settings.showApiValue"
        static let notifications = "settings.notificationsEnabled"
        static let appearance = "settings.appearance"
    }

    static func load(defaults: UserDefaults = .standard) -> AppSettings {
        var settings = AppSettings.default
        if let roots = defaults.array(forKey: Keys.projectRoots) as? [String] {
            settings.projectRootPaths = roots
        }
        if defaults.object(forKey: Keys.refreshMinutes) != nil {
            settings.refreshIntervalMinutes = defaults.double(forKey: Keys.refreshMinutes)
        }
        settings.launchAtLogin = defaults.bool(forKey: Keys.launchAtLogin)
        settings.showCostInMenuBar = defaults.bool(forKey: Keys.showCost)
        // Only override the default (true) when the user has explicitly set this —
        // otherwise a missing key would read `false` and hide the % everyone had.
        if defaults.object(forKey: Keys.showPercent) != nil {
            settings.showPercentInMenuBar = defaults.bool(forKey: Keys.showPercent)
        }
        if defaults.object(forKey: Keys.showApiValue) != nil {
            settings.showApiValue = defaults.bool(forKey: Keys.showApiValue)
        }
        if defaults.object(forKey: Keys.notifications) != nil {
            settings.notificationsEnabled = defaults.bool(forKey: Keys.notifications)
        }
        if let raw = defaults.string(forKey: Keys.appearance), let a = AppAppearance(rawValue: raw) {
            settings.appearance = a
        }
        return settings
    }

    func save(defaults: UserDefaults = .standard) {
        defaults.set(projectRootPaths, forKey: Keys.projectRoots)
        defaults.set(refreshIntervalMinutes, forKey: Keys.refreshMinutes)
        defaults.set(launchAtLogin, forKey: Keys.launchAtLogin)
        defaults.set(showCostInMenuBar, forKey: Keys.showCost)
        defaults.set(showPercentInMenuBar, forKey: Keys.showPercent)
        defaults.set(showApiValue, forKey: Keys.showApiValue)
        defaults.set(notificationsEnabled, forKey: Keys.notifications)
        defaults.set(appearance.rawValue, forKey: Keys.appearance)
    }
}
