import Foundation
import AppKit

/// Manages sandbox-safe access to the user's `~/.claude` folder via a
/// **security-scoped bookmark**. Required for the Mac App Store (sandboxed) build,
/// where the app cannot read arbitrary home-directory paths without a user grant.
///
/// In the non-sandboxed (direct-download) build, `~/.claude/projects` is readable
/// directly, so this is purely additive — `scanRoots()` returns `[]` until the user
/// grants access, and the engine falls back to its default roots.
@MainActor
enum ClaudeFolderAccess {
    private static let bookmarkKey = "access.claudeFolderBookmark.v1"

    /// The granted `~/.claude` URL with its security scope currently open (or nil).
    private(set) static var activeURL: URL?

    static var isGranted: Bool { activeURL != nil }

    /// Restore a previously-granted bookmark and start accessing. Call once on launch.
    static func restore() {
        guard let data = UserDefaults.standard.data(forKey: bookmarkKey) else { return }
        var isStale = false
        guard let url = try? URL(resolvingBookmarkData: data,
                                 options: [.withSecurityScope],
                                 relativeTo: nil,
                                 bookmarkDataIsStale: &isStale) else { return }
        if url.startAccessingSecurityScopedResource() {
            activeURL = url
        }
        if isStale, let fresh = try? url.bookmarkData(options: .withSecurityScope) {
            UserDefaults.standard.set(fresh, forKey: bookmarkKey)
        }
    }

    /// Prompt the user to grant access to their `~/.claude` folder.
    @discardableResult
    static func requestAccess() -> Bool {
        NSApp.activate(ignoringOtherApps: true)
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.showsHiddenFiles = true   // ~/.claude is a hidden dotfile dir
        panel.prompt = "Grant Access"
        panel.message = "Choose your “.claude” folder so UsageMeter can read Claude Code usage logs. (Nothing leaves your Mac.)"
        panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude", isDirectory: true)

        guard panel.runModal() == .OK, let url = panel.url,
              let data = try? url.bookmarkData(options: .withSecurityScope) else { return false }

        UserDefaults.standard.set(data, forKey: bookmarkKey)
        activeURL?.stopAccessingSecurityScopedResource()
        activeURL = url.startAccessingSecurityScopedResource() ? url : nil
        return isGranted
    }

    /// Revoke the grant (used by a future "reset" / when the path is wrong).
    static func revoke() {
        activeURL?.stopAccessingSecurityScopedResource()
        activeURL = nil
        UserDefaults.standard.removeObject(forKey: bookmarkKey)
    }

    /// Scan roots derived from the grant. The bookmark is the `~/.claude` folder;
    /// the logs live under `projects/`. Returns `[]` when no grant exists.
    static func scanRoots() -> [URL] {
        guard let base = activeURL else { return [] }
        // If the user happened to pick `.../projects` directly, use it as-is.
        if base.lastPathComponent == "projects" { return [base] }
        return [base.appendingPathComponent("projects", isDirectory: true)]
    }
}
