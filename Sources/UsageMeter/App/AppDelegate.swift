import AppKit

/// Keeps the app menu-bar-only: no Dock icon, no app menu window. The Info.plist
/// in the assembled `.app` also sets `LSUIElement = true`; setting the activation
/// policy here makes `swift run` behave the same way during development.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        true
    }
}
