import Foundation
import ServiceManagement

/// Thin wrapper over `SMAppService` for launch-at-login. Requires a real `.app`
/// bundle (a bundle identifier); during an unbundled `swift run` it no-ops so dev
/// builds don't error.
enum LaunchAtLogin {
    static var isAvailable: Bool {
        Bundle.main.bundleIdentifier != nil
    }

    static var isEnabled: Bool {
        guard isAvailable else { return false }
        return SMAppService.mainApp.status == .enabled
    }

    @discardableResult
    static func setEnabled(_ enabled: Bool) -> Bool {
        guard isAvailable else { return false }
        do {
            if enabled {
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                }
            } else {
                if SMAppService.mainApp.status == .enabled {
                    try SMAppService.mainApp.unregister()
                }
            }
            return true
        } catch {
            NSLog("UsageMeter: launch-at-login change failed: \(error.localizedDescription)")
            return false
        }
    }
}
