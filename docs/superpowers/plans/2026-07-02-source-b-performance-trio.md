# Source-B Performance Trio Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix the three measured Source-B performance findings from the deep review: (1) the active session file is fully re-parsed every refresh (60 MB ≈ 0.62 s CPU + ~120 MB transient per tick), (2) cache.json stores 2.4× redundant records (51,819 stored vs 21,591 unique) with nondeterministic project attribution, (3) cache.json is decoded synchronously on the main thread during `AppModel.init`.

**Architecture:** All changes live in `UsageMeterKit`.
- **Append-offset parsing:** `CachedFile` gains `parsedBytes`/`parsedLines`; `JSONLParser.parseIncremental` seeks to the stored offset and parses only the appended tail. Offsets are conservative — only newline-terminated lines are *consumed*; a trailing partial line is still parsed opportunistically (today's behavior) but re-read on the next pass, and the aggregator's dedup drops the repeat. Synthetic-id stability comes from `parsedLines` (`lineIndexBase`), so ids keep today's `project/file#lineIndex` format.
- **Store-time dedup:** `refresh` filters each (re)parsed file's records against a global id set, processing changed files in sorted-path order (deterministic ownership). Because a *removed* file may have owned records that also exist (suppressed) in surviving files, **any removal triggers a full rebuild** — removals are rare (Claude Code's ~30-day transcript pruning), and correctness beats the occasional full re-parse. `DailyAggregator`'s dedup stays as defense in depth; with unique ids its input order no longer affects attribution.
- **Lazy load:** `LocalClaudeCodeSource` loads the cache on first *access* (inside the `DataEngine` actor, off the main thread) instead of in `init` (which runs on the main thread during `AppModel.init`).
- **Cache v3 → v4:** one bump so the whole store is rebuilt deduped + offset-annotated on first launch (a one-time full re-parse — the same work every launch did before the mtime fix).

**Tech Stack:** Swift 6, swift-testing, SwiftPM. TDD per task; `swift test` green before every commit.

## Global Constraints

- Privacy hard rule unchanged: parser reads only the whitelisted `message.usage.*` fields.
- Append fast path assumption (documented + tested): Claude Code session logs are append-only. A prefix edit with size growth is NOT detected until a size-shrink/equal-size change forces a full re-parse — accepted trade-off.
- The empty-scan wipe guard and the conditional-save behavior from the bug batch must keep working (their tests stay green).
- In-memory `cache.lastUpdated` is refreshed on every completed refresh (even no-op) — the popover's "Updated" line depends on it; the FILE is written only when contents changed.
- Work on branch `perf/source-b-trio`; merge to `main` at the end.

---

### Task 0: Branch

- [ ] `git checkout -b perf/source-b-trio`

---

### Task 1: `JSONLParser.parseIncremental` (+ `lineIndexBase`)

**Files:**
- Modify: `Sources/UsageMeterKit/ClaudeCode/JSONLParser.swift`
- Test: `Tests/UsageMeterKitTests/JSONLParserTests.swift`

**Interfaces (produces):**

```swift
public struct IncrementalParseResult: Sendable, Equatable {
    public let records: [UsageRecord]
    /// Absolute offset of the first UNCONSUMED byte (start of the trailing partial line, if any).
    public let parsedBytes: Int
    /// Newline-terminated lines consumed up to `parsedBytes` (absolute; feeds the next call's `lineIndexBase`).
    public let parsedLines: Int
}
public func parseIncremental(fileAt url: URL, projectID: String,
                             fromByteOffset: Int = 0, lineIndexBase: Int = 0) -> IncrementalParseResult
// parse(data:projectID:source:) gains `lineIndexBase: Int = 0` (defaulted — source compatible)
```

- [ ] **Step 1.1: Failing tests** — append to `JSONLParserTests`:

```swift
    private func line(_ id: Int) -> String {
        #"{"type":"assistant","requestId":"inc-\#(id)","timestamp":"2026-07-01T10:00:0\#(id % 10).000Z","message":{"model":"claude-opus-4-8","usage":{"output_tokens":1}}}"#
    }

    @Test func incrementalParseConsumesOnlyCompleteLines() throws {
        let fm = FileManager.default
        let url = fm.temporaryDirectory.appendingPathComponent("inc-\(UUID().uuidString).jsonl")
        defer { try? fm.removeItem(at: url) }
        let complete = line(1) + "\n" + line(2) + "\n"
        let partial = #"{"type":"assistant","requestId":"inc-3","time"#   // torn mid-write
        try Data((complete + partial).utf8).write(to: url)

        let result = parser.parseIncremental(fileAt: url, projectID: "p")
        #expect(result.records.count == 2)                     // partial line skipped
        #expect(result.parsedBytes == Data(complete.utf8).count) // …and NOT consumed
        #expect(result.parsedLines == 2)
    }

    @Test func incrementalResumeMatchesOneShotParse() throws {
        let fm = FileManager.default
        let url = fm.temporaryDirectory.appendingPathComponent("inc-\(UUID().uuidString).jsonl")
        defer { try? fm.removeItem(at: url) }
        // Include a record WITHOUT requestId/uuid so synthetic-id continuity is exercised.
        let noID = #"{"type":"assistant","timestamp":"2026-07-01T10:00:05.000Z","message":{"model":"claude-opus-4-8","usage":{"output_tokens":9}}}"#
        try Data((line(1) + "\n" + line(2) + "\n").utf8).write(to: url)

        let first = parser.parseIncremental(fileAt: url, projectID: "p")
        try Data((line(1) + "\n" + line(2) + "\n" + noID + "\n" + line(4) + "\n").utf8).write(to: url)
        let second = parser.parseIncremental(fileAt: url, projectID: "p",
                                             fromByteOffset: first.parsedBytes,
                                             lineIndexBase: first.parsedLines)

        let oneShot = parser.parseIncremental(fileAt: url, projectID: "p")
        #expect((first.records + second.records).map(\.id) == oneShot.records.map(\.id))
        #expect(second.parsedBytes == oneShot.parsedBytes)
        #expect(second.parsedLines == oneShot.parsedLines)
    }

    @Test func incrementalParseOfMissingFileIsEmptyAndKeepsOffsets() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("gone-\(UUID().uuidString).jsonl")
        let result = parser.parseIncremental(fileAt: url, projectID: "p", fromByteOffset: 42, lineIndexBase: 7)
        #expect(result.records.isEmpty)
        #expect(result.parsedBytes == 42)
        #expect(result.parsedLines == 7)
    }
```

- [ ] **Step 1.2:** `swift test --filter JSONLParserTests` → compile error (red).
- [ ] **Step 1.3: Implement.** In `JSONLParser.swift`:
  1. Add the `IncrementalParseResult` struct (file scope, above the parser).
  2. Thread `lineIndexBase` through: `parse(data:projectID:source:lineIndexBase:)` (default 0) → private `parse(text:...)` starts `var lineIndex = lineIndexBase - 1`.
  3. Add:

```swift
    /// Incremental parse for append-only session logs: seek to `fromByteOffset`,
    /// parse the tail. Only newline-terminated lines are CONSUMED (offsets move
    /// past them); a trailing partial line is still parsed opportunistically —
    /// same completeness as the whole-file parse — but will be re-read next
    /// pass, and the aggregator's id-dedup drops the repeat. `lineIndexBase`
    /// keeps synthetic ids (`project/file#line`) identical to a one-shot parse.
    public func parseIncremental(
        fileAt url: URL,
        projectID: String,
        fromByteOffset offset: Int = 0,
        lineIndexBase: Int = 0
    ) -> IncrementalParseResult {
        guard let handle = try? FileHandle(forReadingFrom: url) else {
            return IncrementalParseResult(records: [], parsedBytes: offset, parsedLines: lineIndexBase)
        }
        defer { try? handle.close() }
        guard (try? handle.seek(toOffset: UInt64(offset))) != nil,
              let data = try? handle.readToEnd(), !data.isEmpty else {
            return IncrementalParseResult(records: [], parsedBytes: offset, parsedLines: lineIndexBase)
        }
        var consumedBytes = 0
        var consumedLines = 0
        if let lastNewline = data.lastIndex(of: 0x0A) {
            consumedBytes = lastNewline + 1
            consumedLines = data[..<consumedBytes].reduce(into: 0) { if $1 == 0x0A { $0 += 1 } }
        }
        let records = parse(data: data, projectID: projectID,
                            source: url.lastPathComponent, lineIndexBase: lineIndexBase)
        return IncrementalParseResult(records: records,
                                      parsedBytes: offset + consumedBytes,
                                      parsedLines: lineIndexBase + consumedLines)
    }
```

- [ ] **Step 1.4:** `swift test` → green.
- [ ] **Step 1.5:** Commit: `"Kit: incremental JSONL parsing (byte offset + stable synthetic line ids)"`

---

### Task 2: Append fast path in `LocalClaudeCodeSource` + cache v4

**Files:**
- Modify: `Sources/UsageMeterKit/Store/UsageStore.swift` (`CachedFile` fields; `currentVersion = 4`)
- Modify: `Sources/UsageMeterKit/ClaudeCode/ClaudeCodeSource.swift` (`refresh` rewrite; see Task 3 — implemented together but committed after its own tests)
- Test: `Tests/UsageMeterKitTests/AdditionalCoverageTests.swift` (`LocalClaudeCodeSourceRobustnessTests`)

**Interfaces (produces):** `CachedFile(stamp:projectID:records:parsedBytes:parsedLines:)` (new params default 0). `CacheData.currentVersion == 4`.

- [ ] **Step 2.1: Failing tests** — append to `LocalClaudeCodeSourceRobustnessTests`:

```swift
    @Test func appendFastPathReadsOnlyTheTail() throws {
        let (root, storeDir) = try makeRootAndStore()
        defer { try? fm.removeItem(at: root); try? fm.removeItem(at: storeDir) }
        let session = root.appendingPathComponent("projA/s1.jsonl")
        let store = UsageStore(directory: storeDir)
        let source = LocalClaudeCodeSource(store: store, pricing: .defaults)
        _ = source.refresh(roots: [root], now: Date(timeIntervalSince1970: 1_800_000_000))

        // Grow the file: REWRITE the first line with a new id AND append one.
        // The fast path must pick up only the appended tail — the prefix edit
        // stays invisible (append-only trade-off, fixed by any shrink).
        let rewritten = #"{"type":"assistant","requestId":"r1-EDITED","timestamp":"2026-06-30T10:00:00.000Z","message":{"model":"claude-opus-4-8","usage":{"output_tokens":100}}}"#
        let appended = #"{"type":"assistant","requestId":"r-tail","timestamp":"2026-06-30T12:00:00.000Z","message":{"model":"claude-opus-4-8","usage":{"output_tokens":7}}}"#
        try Data((rewritten + "\n" + appended + "\n").utf8).write(to: session)

        let stats = source.refresh(roots: [root], now: Date(timeIntervalSince1970: 1_800_000_060))
        let cached = UsageStore(directory: storeDir).load().files.values.first
        let ids = Set((cached?.records ?? []).map(\.id))
        #expect(ids.contains("r1"))          // prefix NOT re-read
        #expect(!ids.contains("r1-EDITED"))
        #expect(ids.contains("r-tail"))      // tail parsed
        #expect(stats.recordCount == 2)
        #expect((cached?.parsedBytes ?? 0) > 0)
    }

    @Test func shrinkForcesFullReparse() throws {
        let (root, storeDir) = try makeRootAndStore()
        defer { try? fm.removeItem(at: root); try? fm.removeItem(at: storeDir) }
        let session = root.appendingPathComponent("projA/s1.jsonl")
        let source = LocalClaudeCodeSource(store: UsageStore(directory: storeDir), pricing: .defaults)
        _ = source.refresh(roots: [root], now: Date(timeIntervalSince1970: 1_800_000_000))

        let replacement = #"{"type":"assistant","requestId":"r-new","timestamp":"2026-06-30T13:00:00.000Z","message":{"model":"claude-opus-4-8","usage":{"output_tokens":5}}}"#
        try Data((replacement + "\n").utf8).write(to: session)   // smaller than before

        let stats = source.refresh(roots: [root], now: Date(timeIntervalSince1970: 1_800_000_060))
        #expect(stats.recordCount == 1)
        #expect(stats.total.outputTokens == 5)
    }
```

- [ ] **Step 2.2:** Red (compile error on `parsedBytes` or assertion failures).
- [ ] **Step 2.3: Implement `CachedFile` + v4** in `UsageStore.swift`:

```swift
public struct CachedFile: Codable, Sendable, Equatable {
    public var stamp: FileStamp
    public var projectID: String
    public var records: [UsageRecord]
    /// Byte offset of the first unparsed byte — the append-only fast path
    /// resumes here instead of re-reading the whole (possibly 60 MB) file.
    public var parsedBytes: Int
    /// Complete lines consumed up to `parsedBytes` (keeps synthetic ids stable).
    public var parsedLines: Int

    public init(stamp: FileStamp, projectID: String, records: [UsageRecord],
                parsedBytes: Int = 0, parsedLines: Int = 0) {
        self.stamp = stamp
        self.projectID = projectID
        self.records = records
        self.parsedBytes = parsedBytes
        self.parsedLines = parsedLines
    }
}
```

and bump the version comment + constant:

```swift
    /// v3: `TokenUsage` gained `cacheCreation1hTokens` (cache_creation TTL split).
    /// v4: `CachedFile` gained `parsedBytes`/`parsedLines` (append-offset parsing)
    /// and records are stored globally deduped; bumping forces one rebuild.
    public static let currentVersion = 4
```

- [ ] **Step 2.4:** Implement `refresh` (full rewrite, shared with Task 3 — see Task 3 Step 3.3 for the complete body). For THIS task's commit, the dedup filter may already be included (it does not affect these tests: unique ids).
- [ ] **Step 2.5:** `swift test` → green (fix any test constructing `CachedFile`/`CacheData` with `version: 3` by using `CacheData.currentVersion`).
- [ ] **Step 2.6:** Commit: `"Append-offset parsing: active session files parse only the appended tail (cache v4)"`

---

### Task 3: Store-time global dedup + removal-safe rebuild

**Files:**
- Modify: `Sources/UsageMeterKit/ClaudeCode/ClaudeCodeSource.swift`
- Test: `Tests/UsageMeterKitTests/AdditionalCoverageTests.swift`

- [ ] **Step 3.1: Failing tests:**

```swift
    @Test func crossFileDuplicateIsStoredOnceWithDeterministicOwner() throws {
        let (root, storeDir) = try makeRootAndStore()   // projA/s1.jsonl holds r1
        defer { try? fm.removeItem(at: root); try? fm.removeItem(at: storeDir) }
        // A resumed session in projB repeats r1 verbatim and adds r2.
        let dupe = #"{"type":"assistant","requestId":"r1","timestamp":"2026-06-30T10:00:00.000Z","message":{"model":"claude-opus-4-8","usage":{"output_tokens":100}}}"#
        let fresh = #"{"type":"assistant","requestId":"r2","timestamp":"2026-06-30T11:00:00.000Z","message":{"model":"claude-opus-4-8","usage":{"output_tokens":50}}}"#
        let resumed = root.appendingPathComponent("projB/s2.jsonl")
        try fm.createDirectory(at: resumed.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data((dupe + "\n" + fresh + "\n").utf8).write(to: resumed)

        let store = UsageStore(directory: storeDir)
        let source = LocalClaudeCodeSource(store: store, pricing: .defaults)
        let stats = source.refresh(roots: [root], now: Date(timeIntervalSince1970: 1_800_000_000))
        #expect(stats.recordCount == 2)

        let cache = UsageStore(directory: storeDir).load()
        let stored = cache.files.values.flatMap(\.records)
        #expect(stored.count == 2)                                   // r1 stored ONCE
        let r1 = stored.first { $0.id == "r1" }
        #expect(r1?.projectID == "projA")                            // sorted-path owner
    }

    @Test func removingTheOwnerFileRecoversTheSharedRecord() throws {
        let (root, storeDir) = try makeRootAndStore()   // projA/s1.jsonl holds r1 (owner)
        defer { try? fm.removeItem(at: root); try? fm.removeItem(at: storeDir) }
        let dupe = #"{"type":"assistant","requestId":"r1","timestamp":"2026-06-30T10:00:00.000Z","message":{"model":"claude-opus-4-8","usage":{"output_tokens":100}}}"#
        let resumed = root.appendingPathComponent("projB/s2.jsonl")
        try fm.createDirectory(at: resumed.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data((dupe + "\n").utf8).write(to: resumed)

        let source = LocalClaudeCodeSource(store: UsageStore(directory: storeDir), pricing: .defaults)
        _ = source.refresh(roots: [root], now: Date(timeIntervalSince1970: 1_800_000_000))

        // Prune the owner. The suppressed copy in projB must be recovered
        // (removals trigger a full rebuild), not silently lost.
        try fm.removeItem(at: root.appendingPathComponent("projA/s1.jsonl"))
        let stats = source.refresh(roots: [root], now: Date(timeIntervalSince1970: 1_800_000_060))
        #expect(stats.recordCount == 1)
        #expect(stats.total.outputTokens == 100)
    }
```

- [ ] **Step 3.2:** Red (`stored.count == 3`, and the removal test loses r1).
- [ ] **Step 3.3: Implement** — replace `refresh` in `ClaudeCodeSource.swift`:

```swift
    public func refresh(roots: [URL], now: Date) -> ClaudeCodeStats {
        var diff = scanner.diff(roots: roots, against: cache.stamps)

        // Wipe guard: a scan that finds NOTHING while the cache has data means
        // the roots are temporarily unreachable (sandbox bookmark failed to
        // resolve, volume unmounted) — not that every session file vanished.
        // Treating it as removal would zero all stats AND persist the wipe.
        // Serve the cached aggregate; the next successful scan resyncs.
        if diff.changed.isEmpty, diff.unchanged.isEmpty, !cache.files.isEmpty {
            return aggregate(now: now)
        }

        // Records are stored globally deduped, so a REMOVED file may have owned
        // records whose suppressed copies live in surviving files. Rebuild from
        // scratch to recover them — removals are rare (transcript pruning).
        if !diff.removedPaths.isEmpty {
            cache.files.removeAll()
            diff = scanner.diff(roots: roots, against: [:])
        }

        guard !diff.changed.isEmpty else {
            cache.lastUpdated = now   // freshness for the UI; nothing to persist
            return aggregate(now: now)
        }

        // Ids owned by files NOT being re-parsed this pass.
        let changedPaths = Set(diff.changed.map(\.path))
        var ownedIDs = Set<String>()
        for (path, cached) in cache.files where !changedPaths.contains(path) {
            for record in cached.records { ownedIDs.insert(record.id) }
        }

        // Sorted-path order → deterministic duplicate ownership.
        for file in diff.changed.sorted(by: { $0.path < $1.path }) {
            let previous = cache.files[file.path]
            var kept: [UsageRecord]
            let parsed: IncrementalParseResult
            if let previous, previous.parsedBytes > 0, file.size > previous.stamp.size {
                // Append-only fast path: session logs only grow. A prefix edit
                // that also grows the file is invisible until a shrink/equal-size
                // change forces the full re-parse below — accepted trade-off.
                parsed = parser.parseIncremental(
                    fileAt: file.url, projectID: file.projectID,
                    fromByteOffset: previous.parsedBytes, lineIndexBase: previous.parsedLines)
                kept = previous.records
            } else {
                parsed = parser.parseIncremental(fileAt: file.url, projectID: file.projectID)
                kept = []
            }
            for record in kept { ownedIDs.insert(record.id) }
            for record in parsed.records where ownedIDs.insert(record.id).inserted {
                kept.append(record)
            }
            cache.files[file.path] = CachedFile(
                stamp: FileStamp(modifiedAt: file.modifiedAt, size: file.size),
                projectID: file.projectID,
                records: kept,
                parsedBytes: parsed.parsedBytes,
                parsedLines: parsed.parsedLines
            )
        }

        cache.lastUpdated = now
        store.save(cache)
        return aggregate(now: now)
    }
```

- [ ] **Step 3.4:** `swift test` → ALL green — pay attention to the pre-existing suites: `genuineRemovalStillDropsRecords` (removal now rebuilds — same observable outcome), `noOpRefreshDoesNotRewriteTheCacheFile`, `emptyScanWithNonEmptyCacheDoesNotWipeStats`, DataEngine end-to-end, dedup/aggregator suites.
- [ ] **Step 3.5:** Commit: `"Store-time global dedup with deterministic ownership; removals rebuild the cache"`

---

### Task 4: Lazy cache load (main-thread launch stall)

**Files:**
- Modify: `Sources/UsageMeterKit/ClaudeCode/ClaudeCodeSource.swift`
- Test: `Tests/UsageMeterKitTests/AdditionalCoverageTests.swift`

- [ ] **Step 4.1: Failing test:**

```swift
    @Test func cacheLoadsLazilyOnFirstAccessNotInit() throws {
        let storeDir = fm.temporaryDirectory.appendingPathComponent("um-lazy-\(UUID().uuidString)", isDirectory: true)
        defer { try? fm.removeItem(at: storeDir) }
        let store = UsageStore(directory: storeDir)

        // Seed cache A on disk, construct the source, then REPLACE with cache B
        // before anything is accessed. A lazy loader sees B; an eager init
        // would have latched A.
        let record = UsageRecord(id: "lazy-1", model: "claude-opus-4-8",
                                 timestamp: Date(timeIntervalSince1970: 1_800_000_000),
                                 usage: TokenUsage(outputTokens: 1), projectID: "p")
        store.save(CacheData(files: ["a": CachedFile(
            stamp: FileStamp(modifiedAt: Date(timeIntervalSince1970: 1), size: 1),
            projectID: "p", records: [])]))
        let source = LocalClaudeCodeSource(store: store, pricing: .defaults)
        store.save(CacheData(files: ["b": CachedFile(
            stamp: FileStamp(modifiedAt: Date(timeIntervalSince1970: 2), size: 2),
            projectID: "p", records: [record])]))

        let stats = source.cachedStats(now: Date(timeIntervalSince1970: 1_800_000_100))
        #expect(stats.recordCount == 1)   // saw cache B → load happened on access
    }
```

- [ ] **Step 4.2:** Red (eager init latches cache A → recordCount 0).
- [ ] **Step 4.3: Implement** in `LocalClaudeCodeSource`:

```swift
    /// Loaded on FIRST ACCESS, not in `init`: `init` runs synchronously inside
    /// `@MainActor AppModel.init` at launch, while every access happens inside
    /// the `DataEngine` actor — so the (growing-with-history) JSON decode moves
    /// off the main thread.
    private var cacheStorage: CacheData?
    private var cache: CacheData {
        get {
            if cacheStorage == nil { cacheStorage = store.load() }
            return cacheStorage!
        }
        set { cacheStorage = newValue }
    }
```

and change `init` to not touch the store (delete `self.cache = store.load()`), `reset()` sets `cacheStorage = .empty` after `store.clear()`.

- [ ] **Step 4.4:** `swift test` → green.
- [ ] **Step 4.5:** Commit: `"Load the Source-B cache lazily inside the actor (no main-thread launch stall)"`

---

### Task 5: Docs, verify, merge

- [ ] **Step 5.1:** `CLAUDE.md`: update the "Incremental scan" note (append-offset + store-dedup + v4) and the `Store/` layout line (`cache.json` v4). `docs/STATUS.md`: add a "What's done" bullet for the perf trio; refresh test counts in both files + README to the final number.
- [ ] **Step 5.2:** `make test` + `swift build -Xswiftc -DAPPSTORE` → green.
- [ ] **Step 5.3:** Merge & push:

```bash
git checkout main
git merge --no-ff perf/source-b-trio -m "Source-B performance trio: append-offset parsing, store-time dedup, lazy cache load"
swift test && git push origin main && git push origin perf/source-b-trio
```

## Self-Review Notes

- **Removal-safety is the load-bearing design decision:** store-time dedup would silently lose suppressed duplicates when the owner file is pruned; the full rebuild on ANY removal makes that impossible (Task 3 test proves it).
- **Synthetic-id stability:** `lineIndexBase` (= stored `parsedLines`) keeps `project/file#line` ids identical between incremental and one-shot parses (Task 1 resume test proves it).
- **No behavior change for the UI:** `cachedStats`/`refresh` signatures unchanged; laziness is invisible except for WHERE the decode happens.
- **v4 bump:** old caches load as `.empty` → one-time full rebuild (deduped + offsets). Same recovery semantics as the v3 bump.
