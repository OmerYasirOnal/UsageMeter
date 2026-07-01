import SwiftUI
import UsageMeterKit

@main
struct UsageMeterApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = AppModel()

    var body: some Scene {
        // The menu-bar item (Source B/C live here in M1; account % arrives in M2).
        MenuBarExtra {
            MenuBarContentView()
                .environmentObject(model)
        } label: {
            MenuBarLabel(model: model)
        }
        .menuBarExtraStyle(.window)

        // Preferences.
        Settings {
            SettingsView()
                .environmentObject(model)
        }

        // Dashboard window (placeholder in M1; built out in M3).
        Window("UsageMeter Dashboard", id: AppWindowID.dashboard) {
            DashboardView()
                .environmentObject(model)
        }
        .defaultSize(width: 920, height: 700)

        // claude.ai login (Source A) — compiled out of the local-only App Store build.
        #if !APPSTORE
        Window("Sign in to claude.ai", id: AppWindowID.accountLogin) {
            AccountLoginScreen(auth: model.accountAuth)
                .environmentObject(model)
        }
        .defaultSize(width: 860, height: 680)
        #endif
    }
}

enum AppWindowID {
    static let dashboard = "dashboard"
    static let accountLogin = "account-login"
}
