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
    /// Alert once per day when today's Claude Code "API value" crosses this
    /// amount (USD). Works from local logs alone — no account needed. 0 = off.
    var dailyBudgetUSD: Double
    /// Color-scheme override.
    var appearance: AppAppearance
    /// Show synthetic sample usage so the app can be previewed before there's any
    /// real Claude Code history. Backs `DemoData.isEnabled` together with the
    /// `USAGEMETER_DEMO` env var.
    var showSampleData: Bool

    static let `default` = AppSettings(
        projectRootPaths: [],
        refreshIntervalMinutes: 1,
        launchAtLogin: false,
        showCostInMenuBar: defaultShowCostInMenuBar,
        showPercentInMenuBar: true,
        showApiValue: true,
        notificationsEnabled: true,
        dailyBudgetUSD: 0,
        appearance: .system,
        showSampleData: false
    )

    /// The App Store build has no account %, so the menu bar would show a bare
    /// glyph by default; start with today's API value visible there instead.
    private static var defaultShowCostInMenuBar: Bool {
        #if APPSTORE
        true
        #else
        false
        #endif
    }

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
        static let dailyBudget = "settings.dailyBudgetUSD"
        static let appearance = "settings.appearance"
        static let showSampleData = DemoData.defaultsKey   // shared with the demo gate
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
        // Only override build-specific / true defaults when the user has explicitly
        // set the key — otherwise a missing key would silently read `false`.
        if defaults.object(forKey: Keys.showCost) != nil {
            settings.showCostInMenuBar = defaults.bool(forKey: Keys.showCost)
        }
        if defaults.object(forKey: Keys.showPercent) != nil {
            settings.showPercentInMenuBar = defaults.bool(forKey: Keys.showPercent)
        }
        if defaults.object(forKey: Keys.showApiValue) != nil {
            settings.showApiValue = defaults.bool(forKey: Keys.showApiValue)
        }
        if defaults.object(forKey: Keys.notifications) != nil {
            settings.notificationsEnabled = defaults.bool(forKey: Keys.notifications)
        }
        if defaults.object(forKey: Keys.dailyBudget) != nil {
            settings.dailyBudgetUSD = defaults.double(forKey: Keys.dailyBudget)
        }
        if let raw = defaults.string(forKey: Keys.appearance), let a = AppAppearance(rawValue: raw) {
            settings.appearance = a
        }
        settings.showSampleData = defaults.bool(forKey: Keys.showSampleData)
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
        defaults.set(dailyBudgetUSD, forKey: Keys.dailyBudget)
        defaults.set(appearance.rawValue, forKey: Keys.appearance)
        defaults.set(showSampleData, forKey: Keys.showSampleData)
    }
}
