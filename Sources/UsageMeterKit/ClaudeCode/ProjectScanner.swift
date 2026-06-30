import Foundation

/// A single session log file discovered on disk.
public struct ScannedFile: Sendable, Equatable, Hashable {
    public let url: URL
    /// Project slug = the first directory under a scan root.
    public let projectID: String
    public let modifiedAt: Date
    public let size: Int

    public init(url: URL, projectID: String, modifiedAt: Date, size: Int) {
        self.url = url
        self.projectID = projectID
        self.modifiedAt = modifiedAt
        self.size = size
    }

    /// Stable cache key.
    public var path: String { url.path }
}

/// The result of comparing a fresh scan against a previous mtime snapshot.
public struct ScanDiff: Sendable, Equatable {
    /// New files or files whose mtime/size changed (must be re-parsed).
    public var changed: [ScannedFile]
    /// Files that are unchanged since last scan (reuse cached records).
    public var unchanged: [ScannedFile]
    /// Paths that existed last time but are gone now (drop cached records).
    public var removedPaths: [String]

    public init(changed: [ScannedFile] = [], unchanged: [ScannedFile] = [], removedPaths: [String] = []) {
        self.changed = changed
        self.unchanged = unchanged
        self.removedPaths = removedPaths
    }
}

/// Discovers Claude Code session JSONL files and supports incremental re-scans.
///
/// Layout: `<root>/<project-slug>/<session-id>.jsonl`, one folder per project.
/// We **skip** any path containing a `subagents` component to avoid double-counting
/// sidechain work at the project/session level (sidechain *records* are also
/// filtered in `JSONLParser`, so we are robust to both layouts).
///
/// `@unchecked Sendable`: the only stored state is a `FileManager`, which Apple
/// documents as thread-safe for the file operations used here.
public struct ProjectScanner: @unchecked Sendable {
    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    /// Default scan roots, in priority order. Both are optional on disk.
    public static func defaultRoots(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> [URL] {
        [
            home.appendingPathComponent(".claude/projects", isDirectory: true),
            home.appendingPathComponent(
                "Library/Developer/Xcode/CodingAssistant/ClaudeAgentConfig/projects",
                isDirectory: true
            )
        ]
    }

    /// Enumerate every session log under the given roots. Missing roots are skipped
    /// (no crash, no error) so a brand-new machine yields an empty list.
    public func scan(roots: [URL]) -> [ScannedFile] {
        var results: [ScannedFile] = []
        for root in roots {
            var isDir: ObjCBool = false
            guard fileManager.fileExists(atPath: root.path, isDirectory: &isDir), isDir.boolValue else {
                continue
            }
            guard let projectDirs = try? fileManager.contentsOfDirectory(
                at: root,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            ) else {
                continue
            }
            for projectDir in projectDirs {
                guard (try? projectDir.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true else {
                    continue
                }
                let projectID = projectDir.lastPathComponent
                results.append(contentsOf: scanProject(projectDir, projectID: projectID))
            }
        }
        return results
    }

    private func scanProject(_ projectDir: URL, projectID: String) -> [ScannedFile] {
        var files: [ScannedFile] = []
        let keys: [URLResourceKey] = [.isDirectoryKey, .contentModificationDateKey, .fileSizeKey]
        guard let enumerator = fileManager.enumerator(
            at: projectDir,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles]
        ) else {
            return files
        }

        for case let url as URL in enumerator {
            // Skip anything under a `subagents/` folder (top-level dedup safety).
            if url.pathComponents.contains("subagents") {
                continue
            }
            guard url.pathExtension.lowercased() == "jsonl" else { continue }
            guard let values = try? url.resourceValues(forKeys: Set(keys)) else { continue }
            if values.isDirectory == true { continue }
            let modifiedAt = values.contentModificationDate ?? Date(timeIntervalSince1970: 0)
            let size = values.fileSize ?? 0
            files.append(ScannedFile(url: url, projectID: projectID, modifiedAt: modifiedAt, size: size))
        }
        return files
    }

    /// Compare a fresh scan against a previous `path -> (mtime, size)` snapshot.
    public func diff(
        roots: [URL],
        against previous: [String: FileStamp]
    ) -> ScanDiff {
        let current = scan(roots: roots)
        var diff = ScanDiff()
        var currentPaths = Set<String>()

        for file in current {
            currentPaths.insert(file.path)
            if let prev = previous[file.path],
               prev.modifiedAt == file.modifiedAt,
               prev.size == file.size {
                diff.unchanged.append(file)
            } else {
                diff.changed.append(file)
            }
        }
        diff.removedPaths = previous.keys.filter { !currentPaths.contains($0) }
        return diff
    }
}

/// A lightweight file fingerprint used to detect changes between scans.
public struct FileStamp: Codable, Sendable, Equatable {
    public var modifiedAt: Date
    public var size: Int

    public init(modifiedAt: Date, size: Int) {
        self.modifiedAt = modifiedAt
        self.size = size
    }
}
