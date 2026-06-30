import SwiftUI
import AppKit

/// Manages the app's activation policy so real windows (login / dashboard /
/// settings) behave like a normal app — focusable, keyboard works, they don't
/// drop behind on Enter — while the app stays a menu-bar-only accessory when no
/// such window is open.
///
/// The policy is derived from ground truth (which titled windows are actually
/// visible) rather than a fragile open/close ref-count, because `NSWindow.close()`
/// often skips SwiftUI's `onDisappear`. A `willClose` observer covers every close
/// path (button, ⌘W, programmatic).
@MainActor
final class WindowPresentation: NSObject {
    static let shared = WindowPresentation()

    private override init() {
        super.init()
        NotificationCenter.default.addObserver(
            self, selector: #selector(windowWillClose(_:)),
            name: NSWindow.willCloseNotification, object: nil)
    }

    /// A managed window appeared → become a regular, focusable app.
    func windowAppeared() {
        setPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowDisappeared() {
        recompute(excluding: nil)
    }

    @objc private func windowWillClose(_ note: Notification) {
        let closing = note.object as? NSWindow
        // The window is still listed during willClose; recompute excluding it.
        Task { @MainActor in self.recompute(excluding: closing) }
    }

    private func recompute(excluding: NSWindow?) {
        let hasManagedWindow = NSApp.windows.contains { window in
            window !== excluding && window.isVisible && window.styleMask.contains(.titled)
        }
        setPolicy(hasManagedWindow ? .regular : .accessory)
    }

    private func setPolicy(_ policy: NSApplication.ActivationPolicy) {
        if NSApp.activationPolicy() != policy {
            NSApp.setActivationPolicy(policy)
        }
    }
}

private struct ManagesActivationPolicy: ViewModifier {
    func body(content: Content) -> some View {
        content
            .onAppear { WindowPresentation.shared.windowAppeared() }
            .onDisappear { WindowPresentation.shared.windowDisappeared() }
    }
}

extension View {
    /// Apply to a window's root view so the app becomes a regular (focusable) app
    /// while the window is open and reverts to a menu-bar accessory when it closes.
    func managesActivationPolicy() -> some View { modifier(ManagesActivationPolicy()) }
}
