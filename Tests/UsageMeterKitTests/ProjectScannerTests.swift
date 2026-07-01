import Testing
import Foundation
@testable import UsageMeterKit

@Suite struct ProjectScannerTests {
    let fm = FileManager.default

    func makeTempRoot() throws -> URL {
        let root = fm.temporaryDirectory.appendingPathComponent("um-scan-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        // Resolve the /var -> /private/var symlink so test paths match the
        // canonical paths the scanner emits.
        return root.resolvingSymlinksInPath()
    }

    func write(_ text: String, to url: URL) throws {
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.data(using: .utf8)!.write(to: url)
    }

    func stamps(_ files: [ScannedFile]) -> [String: FileStamp] {
        Dictionary(uniqueKeysWithValues: files.map {
            ($0.path, FileStamp(modifiedAt: $0.modifiedAt, size: $0.size))
        })
    }

    @Test func findsSessionFilesAndSkipsSubagents() throws {
        let root = try makeTempRoot()
        defer { try? fm.removeItem(at: root) }
        try write("{}", to: root.appendingPathComponent("projA/session1.jsonl"))
        try write("{}", to: root.appendingPathComponent("projB/session2.jsonl"))
        try write("{}", to: root.appendingPathComponent("projB/subagents/sub.jsonl"))
        try write("not jsonl", to: root.appendingPathComponent("projB/notes.txt"))

        let files = ProjectScanner().scan(roots: [root])
        let names = Set(files.map { $0.url.lastPathComponent })
        #expect(names == ["session1.jsonl", "session2.jsonl"])
        #expect(files.contains { $0.projectID == "projA" })
        #expect(files.contains { $0.projectID == "projB" })
    }

    @Test func missingRootYieldsEmptyWithoutCrashing() {
        let missing = fm.temporaryDirectory.appendingPathComponent("does-not-exist-\(UUID().uuidString)")
        #expect(ProjectScanner().scan(roots: [missing]).isEmpty)
    }

    @Test func incrementalDiffDetectsNewChangedAndRemoved() throws {
        let root = try makeTempRoot()
        defer { try? fm.removeItem(at: root) }
        let f1 = root.appendingPathComponent("projA/s1.jsonl")
        let f2 = root.appendingPathComponent("projB/s2.jsonl")
        try write("{}", to: f1)
        try write("{}", to: f2)

        let scanner = ProjectScanner()

        // First scan: everything is new.
        let firstDiff = scanner.diff(roots: [root], against: [:])
        #expect(firstDiff.changed.count == 2)
        #expect(firstDiff.unchanged.isEmpty)

        let snapshot = stamps(scanner.scan(roots: [root]))

        // No changes → all unchanged.
        let stable = scanner.diff(roots: [root], against: snapshot)
        #expect(stable.changed.isEmpty)
        #expect(stable.unchanged.count == 2)

        // Append to f1 (size changes) → exactly f1 is changed.
        try write("{}\n{}", to: f1)
        let afterEdit = scanner.diff(roots: [root], against: snapshot)
        #expect(afterEdit.changed.contains { $0.url.lastPathComponent == "s1.jsonl" })
        #expect(afterEdit.unchanged.contains { $0.url.lastPathComponent == "s2.jsonl" })

        // Remove f2 → it shows up as removed. (Compare by suffix: FileManager and
        // URL normalize the /private/var temp prefix differently; production keys
        // are always scanner-produced, so this is purely a test-path concern.)
        try fm.removeItem(at: f2)
        let afterRemove = scanner.diff(roots: [root], against: snapshot)
        #expect(afterRemove.removedPaths.count == 1)
        #expect(afterRemove.removedPaths.contains { $0.hasSuffix("projB/s2.jsonl") })
    }

    @Test func subSecondMtimePrecisionLossIsStillUnchanged() throws {
        // JSONEncoder .iso8601 truncates fractional seconds when the cache is
        // persisted; APFS mtimes are sub-second. A stamp that lost its fractional
        // part must still match, or every relaunch re-parses the whole history.
        let root = try makeTempRoot()
        defer { try? fm.removeItem(at: root) }
        try write("{}", to: root.appendingPathComponent("projA/s1.jsonl"))

        let scanner = ProjectScanner()
        let truncated = Dictionary(uniqueKeysWithValues: scanner.scan(roots: [root]).map {
            ($0.path, FileStamp(
                modifiedAt: Date(timeIntervalSince1970: $0.modifiedAt.timeIntervalSince1970.rounded(.down)),
                size: $0.size))
        })

        let diff = scanner.diff(roots: [root], against: truncated)
        #expect(diff.changed.isEmpty)
        #expect(diff.unchanged.count == 1)
    }

    @Test func mtimeDifferenceOverToleranceIsStillChanged() throws {
        // The tolerance must not swallow real modifications: a stamp 2s older
        // than the file on disk (same size) is a change.
        let root = try makeTempRoot()
        defer { try? fm.removeItem(at: root) }
        try write("{}", to: root.appendingPathComponent("projA/s1.jsonl"))

        let scanner = ProjectScanner()
        let backdated = Dictionary(uniqueKeysWithValues: scanner.scan(roots: [root]).map {
            ($0.path, FileStamp(modifiedAt: $0.modifiedAt.addingTimeInterval(-2), size: $0.size))
        })

        let diff = scanner.diff(roots: [root], against: backdated)
        #expect(diff.changed.count == 1)
        #expect(diff.unchanged.isEmpty)
    }
}
