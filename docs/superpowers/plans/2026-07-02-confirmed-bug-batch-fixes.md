# Confirmed-Bug Batch Fixes Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix the 7 confirmed bugs from the 2026-07-02 deep review in one batch, with a single cache-format version bump (v2 → v3) and no destructive behavior beyond the existing mirror-disk semantics.

**Architecture:** All fixes are in `UsageMeterKit` (SwiftPM library, fully covered by `swift test`) except Task 7, which touches the SwiftUI app target (`Sources/UsageMeter`, no test target — verified by `swift build`). The cache version bumps to 3 exactly once (Task 4) so all existing records are re-parsed with the new `cache_creation` TTL-split data; the mtime-tolerance fix (Task 1) makes that the *last* full re-parse.

**Tech Stack:** Swift 6, swift-testing (`@Test` / `#expect`), SwiftPM. Run tests with `swift test` (or `make test`). No network or real user data needed.

## Global Constraints

- Privacy hard rule: the parser may only read `type`, `isSidechain`, `requestId`, `uuid`, `timestamp`, `message.model`, `message.usage.*`. The new `cache_creation` split object lives under `message.usage.*` — allowed. Never read message content.
- Official pricing (verified 2026-07-02 via the claude-api reference, cached 2026-06-24): Opus 4.8/4.7/4.6 = $5/$25 per MTok; Sonnet = $3/$15; Haiku 4.5 = $1/$5; Fable 5 = $10/$50; Mythos 5 = $10/$50. Cache write ×1.25 (5-min TTL) / ×2.0 (1-hour TTL); cache read ×0.10.
- `pricing.json` and `Pricing.defaults` must stay byte-for-byte in sync (values, not formatting).
- Design intent preserved: 401 must NOT serve stale account data indefinitely (see `Tests/UsageMeterKitTests/AccountTests.swift:294`). The account grace window is bounded at 30 minutes.
- Work on branch `fix/deep-review-bug-batch`; merge to `main` at the end (Task 8).
- Every task ends with `swift test` green before committing.

---

### Task 0: Branch

- [ ] **Step 0.1: Create the work branch**

```bash
cd /Users/omeryasironal/Projects/usage-meter
git checkout -b fix/deep-review-bug-batch
```

---

### Task 1: ProjectScanner mtime tolerance (incremental cache defeated across relaunches)

**Bug:** `UsageStore` encodes `FileStamp.modifiedAt` with `JSONEncoder.dateEncodingStrategy = .iso8601`, which truncates fractional seconds. APFS mtimes are sub-second. `ProjectScanner.diff` compares with exact `Date` equality, so after every relaunch every file classifies as changed and the whole history re-parses.

**Files:**
- Modify: `Sources/UsageMeterKit/ClaudeCode/ProjectScanner.swift:129-131`
- Test: `Tests/UsageMeterKitTests/ProjectScannerTests.swift`

**Interfaces:**
- Produces: `ProjectScanner.diff` treats stamps whose mtime differs by `< 1.0s` (and equal size) as unchanged. No signature changes.

- [ ] **Step 1.1: Write the failing tests** — append inside `@Suite struct ProjectScannerTests` in `Tests/UsageMeterKitTests/ProjectScannerTests.swift`:

```swift
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
```

- [ ] **Step 1.2: Run tests to verify the first fails**

Run: `swift test --filter ProjectScannerTests`
Expected: `subSecondMtimePrecisionLossIsStillUnchanged` FAILS (diff.changed == 1); `mtimeDifferenceOverToleranceIsStillChanged` passes (exact equality is stricter).

- [ ] **Step 1.3: Implement the tolerance** — in `Sources/UsageMeterKit/ClaudeCode/ProjectScanner.swift`, replace the comparison in `diff`:

```swift
        for file in current {
            currentPaths.insert(file.path)
            // Sub-second tolerance: the persisted stamp round-trips through an
            // ISO-8601 encoder that drops fractional seconds, while APFS mtimes
            // are sub-second — exact equality would re-parse everything on every
            // relaunch. A real modification moves the mtime by ≥ 1s or changes
            // the size (and the next tick re-checks regardless).
            if let prev = previous[file.path],
               abs(prev.modifiedAt.timeIntervalSince(file.modifiedAt)) < 1.0,
               prev.size == file.size {
                diff.unchanged.append(file)
            } else {
                diff.changed.append(file)
            }
        }
```

- [ ] **Step 1.4: Run the full suite**

Run: `swift test`
Expected: all tests PASS.

- [ ] **Step 1.5: Commit**

```bash
git add Sources/UsageMeterKit/ClaudeCode/ProjectScanner.swift Tests/UsageMeterKitTests/ProjectScannerTests.swift
git commit -m "Fix incremental cache defeat: tolerate sub-second mtime loss in diff"
```

---

### Task 2: LocalClaudeCodeSource — skip no-op saves + guard against empty-scan cache wipe

**Bugs:** (a) `refresh` rewrites the entire cache.json (~13 MB measured) every tick even when nothing changed (~19 GB/day of SSD writes at the 1-min default). (b) A temporarily unavailable scan root (e.g. the APPSTORE sandbox bookmark failing to resolve) makes `scan` return `[]`, so every cached path lands in `removedPaths`, and the wipe is persisted — all stats drop to zero.

**Files:**
- Modify: `Sources/UsageMeterKit/ClaudeCode/ClaudeCodeSource.swift:49-66`
- Test: `Tests/UsageMeterKitTests/AdditionalCoverageTests.swift` (new suite at end of file)

**Interfaces:**
- Consumes: `ScanDiff` from Task 1 (unchanged shape).
- Produces: `refresh(roots:now:)` (same signature) that (a) only calls `store.save` when `diff.changed` or `diff.removedPaths` is non-empty, and (b) returns the cached aggregate untouched when the scan finds zero files but the cache is non-empty.

- [ ] **Step 2.1: Write the failing tests** — append at the end of `Tests/UsageMeterKitTests/AdditionalCoverageTests.swift` (after the `CountingAccountClient` class):

```swift
@Suite struct LocalClaudeCodeSourceRobustnessTests {
    let fm = FileManager.default

    private func makeRootAndStore() throws -> (root: URL, storeDir: URL) {
        let root = fm.temporaryDirectory
            .appendingPathComponent("um-src-\(UUID().uuidString)", isDirectory: true)
            .resolvingSymlinksInPath()
        let storeDir = fm.temporaryDirectory
            .appendingPathComponent("um-src-store-\(UUID().uuidString)", isDirectory: true)
        let session = root.appendingPathComponent("projA/s1.jsonl")
        try fm.createDirectory(at: session.deletingLastPathComponent(), withIntermediateDirectories: true)
        let line = #"{"type":"assistant","requestId":"r1","timestamp":"2026-06-30T10:00:00.000Z","message":{"model":"claude-opus-4-8","usage":{"output_tokens":100}}}"#
        try Data((line + "\n").utf8).write(to: session)
        return (root, storeDir)
    }

    @Test func noOpRefreshDoesNotRewriteTheCacheFile() throws {
        let (root, storeDir) = try makeRootAndStore()
        defer { try? fm.removeItem(at: root); try? fm.removeItem(at: storeDir) }
        let store = UsageStore(directory: storeDir)
        let source = LocalClaudeCodeSource(store: store, pricing: .defaults)

        _ = source.refresh(roots: [root], now: Date(timeIntervalSince1970: 1_800_000_000))
        let firstWrite = try Data(contentsOf: store.fileURL)

        // Nothing on disk changed → the cache file must not be rewritten
        // (a rewrite would at minimum change the persisted lastUpdated).
        _ = source.refresh(roots: [root], now: Date(timeIntervalSince1970: 1_800_000_060))
        let secondWrite = try Data(contentsOf: store.fileURL)
        #expect(firstWrite == secondWrite)
    }

    @Test func emptyScanWithNonEmptyCacheDoesNotWipeStats() throws {
        let (root, storeDir) = try makeRootAndStore()
        defer { try? fm.removeItem(at: root); try? fm.removeItem(at: storeDir) }
        let store = UsageStore(directory: storeDir)
        let source = LocalClaudeCodeSource(store: store, pricing: .defaults)

        let seeded = source.refresh(roots: [root], now: Date(timeIntervalSince1970: 1_800_000_000))
        #expect(seeded.recordCount == 1)

        // Root temporarily unavailable (sandbox bookmark failure, unmounted
        // volume): the scan finds nothing. Stats and the persisted cache must
        // survive rather than being wiped to zero.
        let missing = fm.temporaryDirectory.appendingPathComponent("um-gone-\(UUID().uuidString)")
        let afterOutage = source.refresh(roots: [missing], now: Date(timeIntervalSince1970: 1_800_000_060))
        #expect(afterOutage.recordCount == 1)
        #expect(afterOutage.total.outputTokens == 100)

        let reloaded = UsageStore(directory: storeDir).load()
        #expect(!reloaded.files.isEmpty)
    }

    @Test func genuineRemovalStillDropsRecords() throws {
        // The wipe guard must not break normal removal semantics: when the scan
        // still sees the root but one file is gone, its records are dropped.
        let (root, storeDir) = try makeRootAndStore()
        defer { try? fm.removeItem(at: root); try? fm.removeItem(at: storeDir) }
        let extra = root.appendingPathComponent("projB/s2.jsonl")
        try fm.createDirectory(at: extra.deletingLastPathComponent(), withIntermediateDirectories: true)
        let line = #"{"type":"assistant","requestId":"r2","timestamp":"2026-06-30T11:00:00.000Z","message":{"model":"claude-opus-4-8","usage":{"output_tokens":50}}}"#
        try Data((line + "\n").utf8).write(to: extra)

        let store = UsageStore(directory: storeDir)
        let source = LocalClaudeCodeSource(store: store, pricing: .defaults)
        let seeded = source.refresh(roots: [root], now: Date(timeIntervalSince1970: 1_800_000_000))
        #expect(seeded.recordCount == 2)

        try fm.removeItem(at: extra)
        let afterRemove = source.refresh(roots: [root], now: Date(timeIntervalSince1970: 1_800_000_060))
        #expect(afterRemove.recordCount == 1)
    }
}
```

- [ ] **Step 2.2: Run tests to verify they fail**

Run: `swift test --filter LocalClaudeCodeSourceRobustnessTests`
Expected: `noOpRefreshDoesNotRewriteTheCacheFile` FAILS (lastUpdated changed on disk); `emptyScanWithNonEmptyCacheDoesNotWipeStats` FAILS (recordCount == 0); `genuineRemovalStillDropsRecords` PASSES (current behavior).

- [ ] **Step 2.3: Implement** — replace `refresh` in `Sources/UsageMeterKit/ClaudeCode/ClaudeCodeSource.swift`:

```swift
    public func refresh(roots: [URL], now: Date) -> ClaudeCodeStats {
        let diff = scanner.diff(roots: roots, against: cache.stamps)

        // Wipe guard: a scan that finds NOTHING while the cache has data means
        // the roots are temporarily unreachable (sandbox bookmark failed to
        // resolve, volume unmounted) — not that every session file vanished.
        // Treating it as removal would zero all stats AND persist the wipe.
        // Serve the cached aggregate; the next successful scan resyncs.
        if diff.changed.isEmpty, diff.unchanged.isEmpty, !cache.files.isEmpty {
            return aggregate(now: now)
        }

        for path in diff.removedPaths {
            cache.files.removeValue(forKey: path)
        }
        for file in diff.changed {
            let records = parser.parse(fileAt: file.url, projectID: file.projectID)
            cache.files[file.path] = CachedFile(
                stamp: FileStamp(modifiedAt: file.modifiedAt, size: file.size),
                projectID: file.projectID,
                records: records
            )
        }
        // Unchanged files keep their cached records.
        cache.lastUpdated = now
        // Only rewrite the cache file when its contents actually changed —
        // an unconditional save is a full multi-MB rewrite every tick.
        if !diff.changed.isEmpty || !diff.removedPaths.isEmpty {
            store.save(cache)
        }
        return aggregate(now: now)
    }
```

- [ ] **Step 2.4: Run the full suite**

Run: `swift test`
Expected: all tests PASS. (The DataEngine end-to-end test in `AdditionalCoverageTests` starts from an empty cache and adds files, so the guard and conditional save do not affect it.)

- [ ] **Step 2.5: Commit**

```bash
git add Sources/UsageMeterKit/ClaudeCode/ClaudeCodeSource.swift Tests/UsageMeterKitTests/AdditionalCoverageTests.swift
git commit -m "Stop no-op cache rewrites; guard against empty-scan cache wipe"
```

---

### Task 3: Pricing refresh (Opus 3× over, Fable/Mythos 2× under)

**Bug:** `pricing.json` + `Pricing.defaults` carry opus 15/75 and fable/mythos 5/25. Official rates (verified 2026-07-02): opus 5/25, fable 10/50, mythos 10/50. Sonnet 3/15 and haiku 1/5 are already correct.

**Files:**
- Modify: `Sources/UsageMeterKit/Resources/pricing.json`
- Modify: `Sources/UsageMeterKit/ClaudeCode/Pricing.swift:31-37`
- Modify: `Tests/UsageMeterKitTests/CostCalculatorTests.swift` (expectations use opus 15/75)

**Interfaces:**
- Produces: `Pricing.defaults` with `.opus: ModelRate(input: 5.0, output: 25.0)`, `.fable: ModelRate(input: 10.0, output: 50.0)`, `.mythos: ModelRate(input: 10.0, output: 50.0)`; sonnet/haiku unchanged. Tasks 4–5 tests assume these values.

- [ ] **Step 3.1: Update the expected values in `Tests/UsageMeterKitTests/CostCalculatorTests.swift`** — replace the three opus-rate tests and the total test:

```swift
    @Test func appliesFullCostModel() {
        // opus = input 5 / output 25 per 1M.
        let usage = TokenUsage(inputTokens: 100, cacheCreationTokens: 200,
                               cacheReadTokens: 1000, outputTokens: 50)
        // 100*5 + 200*5*1.25 + 1000*5*0.10 + 50*25 = 500 + 1250 + 500 + 1250 = 3500
        let expected = 3500.0 / 1_000_000.0
        let cost = calc.cost(usage: usage, family: .opus)
        #expect(cost != nil)
        #expect(abs((cost ?? 0) - expected) < 1e-12)
    }

    @Test func cacheReadIsTenPercentOfInputRate() {
        let usage = TokenUsage(cacheReadTokens: 1_000_000)
        // 1,000,000 * 5 * 0.10 / 1,000,000 = 0.5
        #expect(abs((calc.cost(usage: usage, family: .opus) ?? 0) - 0.5) < 1e-9)
    }

    @Test func cacheWriteIs125PercentOfInputRate() {
        let usage = TokenUsage(cacheCreationTokens: 1_000_000)
        // 1,000,000 * 5 * 1.25 / 1,000,000 = 6.25
        #expect(abs((calc.cost(usage: usage, family: .opus) ?? 0) - 6.25) < 1e-9)
    }
```

and in `totalCostSumsPricedAndIgnoresUnpriced` change the comment and expectation:

```swift
    @Test func totalCostSumsPricedAndIgnoresUnpriced() {
        let mixed: [ModelFamily: TokenUsage] = [
            .opus: TokenUsage(outputTokens: 1_000_000),     // 25
            .unknown: TokenUsage(outputTokens: 1_000_000)   // n/a, ignored
        ]
        let total = calc.totalCost(mixed)
        #expect(total != nil)
        #expect(abs((total ?? 0) - 25.0) < 1e-9)
    }
```

(`resolvesFamilyFromModelString` asserts sonnet 15.0 / haiku 5.0 output-rate — unchanged.)

- [ ] **Step 3.2: Run tests to verify they fail**

Run: `swift test --filter CostCalculatorTests`
Expected: the three updated tests FAIL against the old 15/75 rates.

- [ ] **Step 3.3: Update `Sources/UsageMeterKit/Resources/pricing.json`** — full new contents:

```json
{
  "_comment": "ESTIMATES ONLY — not an invoice. Rates are USD per 1,000,000 tokens, verified 2026-07-02 against Anthropic's published prices (https://www.anthropic.com/pricing, https://platform.claude.com/pricing) — re-verify before relying on cost figures. Cache-write tokens bill at input_rate x 1.25 (5-min TTL) or x 2.0 (1-hour TTL); cache-read at input_rate x 0.10 (handled in CostCalculator). The table is family-granular: every version of a family gets the current rate, so legacy Opus <= 4.1 usage ($15/$75 era) is underestimated. Models whose family is not listed here (incl. <synthetic> and local models) are reported as cost n/a.",
  "rates": {
    "opus":   { "input": 5.0,  "output": 25.0 },
    "sonnet": { "input": 3.0,  "output": 15.0 },
    "haiku":  { "input": 1.0,  "output": 5.0 },
    "fable":  { "input": 10.0, "output": 50.0 },
    "mythos": { "input": 10.0, "output": 50.0 }
  }
}
```

- [ ] **Step 3.4: Sync `Pricing.defaults` in `Sources/UsageMeterKit/ClaudeCode/Pricing.swift`** — replace the defaults block:

```swift
    /// Built-in defaults — kept in sync with `Resources/pricing.json`. These are
    /// ESTIMATES (verified 2026-07-02); confirm on Anthropic's official pricing page.
    public static let defaults = Pricing(rates: [
        .opus:   ModelRate(input: 5.0,  output: 25.0),
        .sonnet: ModelRate(input: 3.0,  output: 15.0),
        .haiku:  ModelRate(input: 1.0,  output: 5.0),
        .fable:  ModelRate(input: 10.0, output: 50.0),
        .mythos: ModelRate(input: 10.0, output: 50.0)
    ])
```

- [ ] **Step 3.5: Run the full suite**

Run: `swift test`
Expected: all tests PASS. If any other test hard-codes opus 15/75 (grep `15.0` / `18.75` / `10500` in Tests/), update it the same way.

- [ ] **Step 3.6: Commit**

```bash
git add Sources/UsageMeterKit/Resources/pricing.json Sources/UsageMeterKit/ClaudeCode/Pricing.swift Tests/UsageMeterKitTests/CostCalculatorTests.swift
git commit -m "Update pricing to current official rates (opus 5/25, fable+mythos 10/50)"
```

---

### Task 4: TokenUsage 1h-TTL field + JSONLParser cache_creation split + cache v3

**Bug:** Claude Code logs now carry `usage.cache_creation` as a split object (`ephemeral_5m_input_tokens` / `ephemeral_1h_input_tokens`); measured on this machine, 100% of recent cache-write tokens are 1h-TTL (billed ×2, not ×1.25). The parser reads only the legacy aggregate, and if the legacy field is ever dropped, cache-write silently becomes 0.

**Files:**
- Modify: `Sources/UsageMeterKit/Models/TokenUsage.swift`
- Modify: `Sources/UsageMeterKit/ClaudeCode/JSONLParser.swift:77-82`
- Modify: `Sources/UsageMeterKit/Store/UsageStore.swift:25` (`currentVersion` 2 → 3)
- Test: `Tests/UsageMeterKitTests/JSONLParserTests.swift`

**Interfaces:**
- Produces: `TokenUsage.cacheCreation1hTokens: Int` (new stored property, default 0, subset of `cacheCreationTokens`; NOT added to `totalTokens`). Init signature becomes `TokenUsage(inputTokens:cacheCreationTokens:cacheCreation1hTokens:cacheReadTokens:outputTokens:)` — all defaulted, so existing labeled call sites compile unchanged. `CacheData.currentVersion == 3` (old caches load as `.empty` and re-parse once — same data outcome as the pre-existing mirror-disk semantics, since files pruned from disk were already dropped on every refresh).

- [ ] **Step 4.1: Write the failing tests** — append inside the suite in `Tests/UsageMeterKitTests/JSONLParserTests.swift`:

```swift
    @Test func readsCacheCreationTTLSplit() {
        let line = #"{"type":"assistant","requestId":"r1","timestamp":"2026-07-01T10:00:00.000Z","message":{"model":"claude-fable-5","usage":{"input_tokens":10,"cache_creation_input_tokens":1000,"cache_creation":{"ephemeral_5m_input_tokens":100,"ephemeral_1h_input_tokens":900},"cache_read_input_tokens":5,"output_tokens":7}}}"#
        let records = JSONLParser().parse(data: Data(line.utf8), projectID: "p")
        #expect(records.count == 1)
        #expect(records.first?.usage.cacheCreationTokens == 1000)
        #expect(records.first?.usage.cacheCreation1hTokens == 900)
    }

    @Test func splitWithoutLegacyAggregateStillCountsCacheWrites() {
        // If Claude Code ever drops the legacy aggregate, the split must carry.
        let line = #"{"type":"assistant","requestId":"r2","timestamp":"2026-07-01T10:00:00.000Z","message":{"model":"claude-fable-5","usage":{"cache_creation":{"ephemeral_5m_input_tokens":100,"ephemeral_1h_input_tokens":900},"output_tokens":1}}}"#
        let records = JSONLParser().parse(data: Data(line.utf8), projectID: "p")
        #expect(records.first?.usage.cacheCreationTokens == 1000)
        #expect(records.first?.usage.cacheCreation1hTokens == 900)
    }

    @Test func legacyOnlyCacheWriteHasZeroOneHourPortion() {
        let line = #"{"type":"assistant","requestId":"r3","timestamp":"2026-07-01T10:00:00.000Z","message":{"model":"claude-opus-4-8","usage":{"cache_creation_input_tokens":500,"output_tokens":1}}}"#
        let records = JSONLParser().parse(data: Data(line.utf8), projectID: "p")
        #expect(records.first?.usage.cacheCreationTokens == 500)
        #expect(records.first?.usage.cacheCreation1hTokens == 0)
    }
```

- [ ] **Step 4.2: Run tests to verify they fail**

Run: `swift test --filter JSONLParserTests`
Expected: compile error (`cacheCreation1hTokens` doesn't exist) — that counts as the red step for a model change.

- [ ] **Step 4.3: Extend `TokenUsage`** — replace `Sources/UsageMeterKit/Models/TokenUsage.swift` contents:

```swift
import Foundation

/// The token counts we care about from a Claude Code `message.usage` block.
///
/// Privacy note: these are the *only* numeric fields we ever read from a log line.
/// We never read or store message content. See `JSONLParser`.
public struct TokenUsage: Codable, Sendable, Equatable, Hashable {
    /// Fresh input tokens (not served from / written to cache).
    public var inputTokens: Int
    /// Context written to the prompt cache — ALL TTLs
    /// (`cache_creation_input_tokens`, or the sum of the `cache_creation` split).
    public var cacheCreationTokens: Int
    /// The 1-hour-TTL portion of `cacheCreationTokens`
    /// (`cache_creation.ephemeral_1h_input_tokens`). Billed at 2x the input rate
    /// vs 1.25x for the 5-minute tier — see `CostCalculator`. Always
    /// <= `cacheCreationTokens`; NOT counted again in `totalTokens`.
    public var cacheCreation1hTokens: Int
    /// Context served from the prompt cache (`cache_read_input_tokens`).
    public var cacheReadTokens: Int
    /// Response tokens.
    public var outputTokens: Int

    public init(
        inputTokens: Int = 0,
        cacheCreationTokens: Int = 0,
        cacheCreation1hTokens: Int = 0,
        cacheReadTokens: Int = 0,
        outputTokens: Int = 0
    ) {
        self.inputTokens = inputTokens
        self.cacheCreationTokens = cacheCreationTokens
        self.cacheCreation1hTokens = cacheCreation1hTokens
        self.cacheReadTokens = cacheReadTokens
        self.outputTokens = outputTokens
    }

    public static let zero = TokenUsage()

    /// Every token counted in this record, regardless of bucket.
    /// (`cacheCreation1hTokens` is a sub-bucket of `cacheCreationTokens`,
    /// so it is deliberately not added here.)
    public var totalTokens: Int {
        inputTokens + cacheCreationTokens + cacheReadTokens + outputTokens
    }

    public static func + (lhs: TokenUsage, rhs: TokenUsage) -> TokenUsage {
        TokenUsage(
            inputTokens: lhs.inputTokens + rhs.inputTokens,
            cacheCreationTokens: lhs.cacheCreationTokens + rhs.cacheCreationTokens,
            cacheCreation1hTokens: lhs.cacheCreation1hTokens + rhs.cacheCreation1hTokens,
            cacheReadTokens: lhs.cacheReadTokens + rhs.cacheReadTokens,
            outputTokens: lhs.outputTokens + rhs.outputTokens
        )
    }

    public static func += (lhs: inout TokenUsage, rhs: TokenUsage) {
        lhs = lhs + rhs
    }
}
```

- [ ] **Step 4.4: Parse the split in `JSONLParser`** — in `Sources/UsageMeterKit/ClaudeCode/JSONLParser.swift`, replace the `let usage = TokenUsage(...)` construction:

```swift
            // Cache writes: prefer the legacy aggregate; the `cache_creation`
            // split object (ephemeral_5m/1h) is the forward-compatible source
            // and also tells us the 1h-TTL portion (billed 2x, not 1.25x).
            let legacyCacheWrite = Self.int(usageDict["cache_creation_input_tokens"])
            var oneHourCacheWrite = 0
            var splitTotal = 0
            if let split = usageDict["cache_creation"] as? [String: Any] {
                oneHourCacheWrite = Self.int(split["ephemeral_1h_input_tokens"])
                splitTotal = Self.int(split["ephemeral_5m_input_tokens"]) + oneHourCacheWrite
            }
            let cacheWriteTotal = legacyCacheWrite > 0 ? legacyCacheWrite : splitTotal

            let usage = TokenUsage(
                inputTokens: Self.int(usageDict["input_tokens"]),
                cacheCreationTokens: cacheWriteTotal,
                cacheCreation1hTokens: min(oneHourCacheWrite, cacheWriteTotal),
                cacheReadTokens: Self.int(usageDict["cache_read_input_tokens"]),
                outputTokens: Self.int(usageDict["output_tokens"])
            )
```

Also update the privacy doc comment at the top of the file: change `message.usage.*` enumeration comment (line ~12-14) to mention the `cache_creation` split is read from within `message.usage` — still numeric-only fields.

- [ ] **Step 4.5: Bump the cache version** — in `Sources/UsageMeterKit/Store/UsageStore.swift`:

```swift
    public static let currentVersion = 3
```

Add above it a one-line comment:

```swift
    /// v3: `TokenUsage` gained `cacheCreation1hTokens` (cache_creation TTL split);
    /// bumping forces one full re-parse so existing records pick up 1h data.
```

- [ ] **Step 4.6: Run the full suite**

Run: `swift test`
Expected: all PASS. If a store round-trip test hard-codes `version: 2`, update it to `CacheData.currentVersion`.

- [ ] **Step 4.7: Commit**

```bash
git add Sources/UsageMeterKit/Models/TokenUsage.swift Sources/UsageMeterKit/ClaudeCode/JSONLParser.swift Sources/UsageMeterKit/Store/UsageStore.swift Tests/UsageMeterKitTests/JSONLParserTests.swift
git commit -m "Parse cache_creation TTL split (1h vs 5m) + bump cache to v3"
```

---

### Task 5: CostCalculator 1-hour cache-write multiplier

**Bug:** All cache writes are priced at ×1.25; the 1h-TTL tier bills at ×2.0. On this machine 100% of recent cache writes are 1h.

**Files:**
- Modify: `Sources/UsageMeterKit/ClaudeCode/CostCalculator.swift`
- Test: `Tests/UsageMeterKitTests/CostCalculatorTests.swift`

**Interfaces:**
- Consumes: `TokenUsage.cacheCreation1hTokens` from Task 4; opus rate 5/25 from Task 3.
- Produces: `CostCalculator.cacheWrite1hMultiplier == 2.0`; `cost(usage:family:)` prices the 1h portion at ×2.0 and the remainder at ×1.25.

- [ ] **Step 5.1: Write the failing tests** — append inside `CostCalculatorTests`:

```swift
    @Test func oneHourCacheWritesBillAtDoubleInputRate() {
        let usage = TokenUsage(cacheCreationTokens: 1_000_000, cacheCreation1hTokens: 1_000_000)
        // 1,000,000 * 5 * 2.0 / 1,000,000 = 10.0
        #expect(abs((calc.cost(usage: usage, family: .opus) ?? 0) - 10.0) < 1e-9)
    }

    @Test func mixedTTLCacheWritesSplitTheMultipliers() {
        let usage = TokenUsage(cacheCreationTokens: 1_000_000, cacheCreation1hTokens: 400_000)
        // 600,000*5*1.25 + 400,000*5*2.0 = 3,750,000 + 4,000,000 = 7,750,000 → 7.75
        #expect(abs((calc.cost(usage: usage, family: .opus) ?? 0) - 7.75) < 1e-9)
    }

    @Test func oneHourPortionIsClampedToTheTotal() {
        // Defensive: malformed input where 1h > total must not go negative.
        let usage = TokenUsage(cacheCreationTokens: 100, cacheCreation1hTokens: 200)
        // Clamped to all-1h: 100 * 5 * 2.0 / 1,000,000
        #expect(abs((calc.cost(usage: usage, family: .opus) ?? 0) - (1000.0 / 1_000_000.0)) < 1e-12)
    }
```

- [ ] **Step 5.2: Run tests to verify they fail**

Run: `swift test --filter CostCalculatorTests`
Expected: the three new tests FAIL (all cache writes still priced ×1.25).

- [ ] **Step 5.3: Implement** — in `Sources/UsageMeterKit/ClaudeCode/CostCalculator.swift`, update the header comment and `cost(usage:family:)`:

```swift
/// Turns token counts into estimated USD cost using the Section 4.4 model:
///   fresh input       → input_tokens × input_rate
///   cache write (5m)  → (cache_creation - 1h portion) × input_rate × 1.25
///   cache write (1h)  → cache_creation_1h × input_rate × 2.0
///   cache read        → cache_read_input_tokens × input_rate × 0.10
///   output            → output_tokens × output_rate
/// Rates are per 1,000,000 tokens. Unknown/unpriced families return `nil` (n/a).
public struct CostCalculator: Sendable {
    public static let cacheWriteMultiplier = 1.25
    public static let cacheWrite1hMultiplier = 2.0
    public static let cacheReadMultiplier = 0.10
    private static let perTokenDivisor = 1_000_000.0

    public let pricing: Pricing

    public init(pricing: Pricing) {
        self.pricing = pricing
    }

    /// Estimated cost for a usage bucket attributed to a model family.
    /// Returns `nil` when the family is `.unknown` or has no rate entry.
    public func cost(usage: TokenUsage, family: ModelFamily) -> Double? {
        guard family.isPriced, let rate = pricing.rate(for: family) else { return nil }
        let oneHourWrite = Double(min(usage.cacheCreation1hTokens, usage.cacheCreationTokens))
        let fiveMinWrite = Double(usage.cacheCreationTokens) - oneHourWrite
        let inputCost = Double(usage.inputTokens) * rate.input
        let cacheWriteCost = fiveMinWrite * rate.input * Self.cacheWriteMultiplier
            + oneHourWrite * rate.input * Self.cacheWrite1hMultiplier
        let cacheReadCost = Double(usage.cacheReadTokens) * rate.input * Self.cacheReadMultiplier
        let outputCost = Double(usage.outputTokens) * rate.output
        return (inputCost + cacheWriteCost + cacheReadCost + outputCost) / Self.perTokenDivisor
    }
```

(`cost(usage:model:)` and `totalCost` unchanged.)

- [ ] **Step 5.4: Run the full suite**

Run: `swift test`
Expected: all PASS (records without split data have `cacheCreation1hTokens == 0` → identical costs to before).

- [ ] **Step 5.5: Commit**

```bash
git add Sources/UsageMeterKit/ClaudeCode/CostCalculator.swift Tests/UsageMeterKitTests/CostCalculatorTests.swift
git commit -m "Price 1h-TTL cache writes at 2x input rate (5m stays 1.25x)"
```

---

### Task 6: DataEngine — bounded last-good grace for account fetch failures

**Bug:** `refreshAccount` returns `nil` on any failed fetch even though `lastAccount` holds the last good value — one Wi-Fi blip blanks the popover to the "Log in" state and destroys the burn-projection baselines.

**Design constraint:** `LiveAccountUsageClient` never throws — 401 and "logged out" both surface as `nil`, and 401 must not show stale data indefinitely (`AccountTests.swift:294`). So the grace window is bounded: serve `lastAccount` for at most 30 minutes after its `fetchedAt`, then degrade to local-only. A failed fetch never stamps the politeness floor, so retries stay immediate.

**Files:**
- Modify: `Sources/UsageMeterKit/Engine/DataEngine.swift:92-103`
- Test: `Tests/UsageMeterKitTests/AdditionalCoverageTests.swift`

**Interfaces:**
- Produces: `refreshAccount(now: Date = Date()) async -> AccountUsage?` (additive default param — `refreshAll` keeps calling `refreshAccount()`). New constant `accountStaleTTL: TimeInterval = 30 * 60`.

- [ ] **Step 6.1: Write the failing test** — append inside the `@Suite` that contains `accountFetchIsFloorGuardedWithin60s` in `Tests/UsageMeterKitTests/AdditionalCoverageTests.swift`:

```swift
    @Test func transientAccountFailureServesLastGoodValueBounded() async throws {
        let storeDir = fm.temporaryDirectory.appendingPathComponent("um-eng-grace-\(UUID().uuidString)", isDirectory: true)
        defer { try? fm.removeItem(at: storeDir) }
        let t0 = Date(timeIntervalSince1970: 1_800_000_000)
        let client = ScriptedAccountClient(results: [AccountUsage(session: UsageMetric(percent: 42))])
        let engine = DataEngine(
            configuration: EngineConfiguration(projectRoots: [], refreshInterval: 60),
            recordStore: UsageStore(directory: storeDir),
            statusStore: StatusStore(directory: storeDir),
            statusClient: StubStatusClient(ServiceStatus(indicator: .none, description: "ok")),
            accountClient: client,
            pricing: .defaults,
            calendar: utcCalendar()
        )

        let a = await engine.refreshAccount(now: t0)
        #expect(a?.session?.displayPercent == 42)

        // 2 minutes later the endpoint hiccups (client yields nil): the last
        // good value is served with its ORIGINAL fetchedAt — not a blank UI.
        let b = await engine.refreshAccount(now: t0.addingTimeInterval(120))
        #expect(b?.session?.displayPercent == 42)
        #expect(b?.fetchedAt == a?.fetchedAt)

        // A failed fetch must not stamp the politeness floor — the next
        // trigger retries the endpoint immediately.
        _ = await engine.refreshAccount(now: t0.addingTimeInterval(125))
        #expect(client.calls == 3)

        // 40 minutes in, still failing: the grace window is over → local-only.
        // (Keeps a dead 401 session from showing stale data forever.)
        let c = await engine.refreshAccount(now: t0.addingTimeInterval(40 * 60))
        #expect(c == nil)
    }
```

and append after `CountingAccountClient` at the bottom of the file:

```swift
/// Test double: yields queued results in order (nil = failed / logged-out
/// fetch), then keeps yielding nil. Counts endpoint hits.
final class ScriptedAccountClient: AccountUsageClient, @unchecked Sendable {
    private let lock = NSLock()
    private var results: [AccountUsage?]
    private var _calls = 0
    var calls: Int { lock.withLock { _calls } }
    init(results: [AccountUsage?]) { self.results = results }
    var isAuthenticated: Bool { get async { true } }
    func currentUsage() async throws -> AccountUsage? {
        lock.withLock {
            _calls += 1
            return results.isEmpty ? nil : results.removeFirst()
        }
    }
}
```

- [ ] **Step 6.2: Run tests to verify it fails**

Run: `swift test --filter transientAccountFailureServesLastGoodValueBounded`
Expected: compile error on `refreshAccount(now:)` (no such parameter) — red step for an API addition.

- [ ] **Step 6.3: Implement** — in `Sources/UsageMeterKit/Engine/DataEngine.swift`, add the TTL constant next to `accountFloor`:

```swift
    private static let accountFloor: TimeInterval = 60
    /// How long a last-good account value may be served after a FAILED fetch
    /// before degrading to local-only. Bounded so a dead session (401 → nil)
    /// can't show stale numbers forever, while a transient blip (offline, 5xx,
    /// decode hiccup) doesn't blank the UI and reset burn baselines.
    private static let accountStaleTTL: TimeInterval = 30 * 60
```

and replace `refreshAccount`:

```swift
    /// Refresh Source A. `nil` → local-only mode (never throws to the caller).
    /// Floor-guarded: within `accountFloor` of the last successful fetch it returns
    /// the cached value without touching the network. On a failed fetch the last
    /// good value is served for up to `accountStaleTTL` — carrying its real
    /// `fetchedAt` so the UI can show how old it is — and the floor is NOT
    /// stamped, so the next trigger retries immediately.
    public func refreshAccount(now: Date = Date()) async -> AccountUsage? {
        if let last = lastAccountFetchAt, now.timeIntervalSince(last) < Self.accountFloor {
            return lastAccount
        }
        let fetched = (try? await accountClient.currentUsage()) ?? nil
        guard var usage = fetched else {
            if let lastGood = lastAccount, let fetchedAt = lastGood.fetchedAt,
               now.timeIntervalSince(fetchedAt) < Self.accountStaleTTL {
                return lastGood
            }
            lastAccount = nil
            return nil
        }
        usage.fetchedAt = now          // real fetch time → honest freshness in the UI
        lastAccount = usage
        lastAccountFetchAt = now
        return usage
    }
```

- [ ] **Step 6.4: Run the full suite**

Run: `swift test`
Expected: all PASS — including the existing floor test (`refreshAccount()` default `now` still works) and logout semantics (`clearAccountCache()` nils `lastAccount`, so nothing stale survives an explicit logout).

- [ ] **Step 6.5: Commit**

```bash
git add Sources/UsageMeterKit/Engine/DataEngine.swift Tests/UsageMeterKitTests/AdditionalCoverageTests.swift
git commit -m "Serve last-good account value (bounded 30 min) on transient fetch failure"
```

---

### Task 7: AppModel — auto-refresh survives demo mode; ordered settings application

**Bug:** `bootstrap()` early-returns before `startAutoRefresh()` when "Show sample data" is enabled, so toggling it off later leaves the app permanently stale (exactly the App-Reviewer path). Secondary: `applySettings` dispatches `engine.updateConfiguration` and `refresh()` as two unordered `Task`s, so a refresh can scan the old roots.

**Files:**
- Modify: `Sources/UsageMeter/App/AppModel.swift:119-125` (bootstrap) and `:225-230` (applySettings)

**Interfaces:**
- No API changes. App target has no test target — verification is `swift build` + full `swift test` (kit unaffected).

- [ ] **Step 7.1: Fix `bootstrap()`** — the timer must start regardless of demo mode (`refresh()` already no-ops correctly in demo mode, so a ticking timer is harmless there):

```swift
    /// Show cached values instantly, then do a live refresh and start the timer.
    /// The auto-refresh timer starts even in demo mode: `refresh()` no-ops to
    /// synthetic data while the toggle is on, and keeps ticking with real data
    /// the moment it's turned off (previously the early return left the app
    /// permanently stale after demo → off).
    func bootstrap() async {
        startAutoRefresh()
        if DemoData.isEnabled { snapshot = DemoData.snapshot(); hasLoadedOnce = true; return }
        snapshot = await engine.cachedSnapshot()
        hasLoadedOnce = true
        await refresh()
    }
```

- [ ] **Step 7.2: Order the config-update and refresh in `applySettings`** — replace the two unordered blocks:

```swift
        if newConfig != previousConfig {
            // One ordered task: the refresh must not race the config update,
            // or it can scan the OLD roots.
            Task {
                await engine.updateConfiguration(newConfig)
                if rootsChanged { await self.refresh() }
            }
        }
```

(delete the separate `if rootsChanged { Task { await refresh() } }` block; keep everything else as is.)

- [ ] **Step 7.3: Build + full suite**

Run: `swift build && swift test`
Expected: build succeeds, all tests PASS.

- [ ] **Step 7.4: Commit**

```bash
git add Sources/UsageMeter/App/AppModel.swift
git commit -m "Start auto-refresh even in demo mode; order config update before refresh"
```

---

### Task 8: Docs sync, final verification, merge

**Files:**
- Modify: `CLAUDE.md` (cost model line in "Key implementation notes"; test count)
- Modify: `docs/STATUS.md` (record the batch fix, update test count)

- [ ] **Step 8.1: Update `CLAUDE.md`** — replace the cost-model bullet:

```markdown
- **Cost model** (per 1M tokens): input×rate, cache-write×rate×1.25 (5-min TTL)
  or ×2.0 (1-hour TTL, from the `usage.cache_creation` split),
  cache-read×rate×0.10, output×outputRate. Unknown families (incl. `<synthetic>`)
  → cost `n/a`. Rates verified 2026-07-02 (opus 5/25, sonnet 3/15, haiku 1/5,
  fable/mythos 10/50).
```

- [ ] **Step 8.2: Update `docs/STATUS.md`** — under "What's done", add a bullet recording the batch (date, the 7 fixes, cache v3 one-time re-parse), and refresh the test count in both files to the actual number reported by the final run.

- [ ] **Step 8.3: Final verification**

Run: `make test 2>&1 | tail -3`
Expected: all tests pass (count > 120 — new tests added).

- [ ] **Step 8.4: Commit docs, merge to main, push**

```bash
git add CLAUDE.md docs/STATUS.md
git commit -m "docs: record the confirmed-bug batch fixes (deep review 2026-07-02)"
git checkout main
git merge --no-ff fix/deep-review-bug-batch -m "Fix the 7 confirmed bugs from the 2026-07-02 deep review

- Incremental cache survives relaunches (mtime tolerance)
- No-op refreshes no longer rewrite cache.json every tick
- Empty scan can't wipe cached stats (sandbox bookmark failure)
- Pricing updated to official rates (opus 5/25, fable/mythos 10/50)
- cache_creation TTL split parsed; 1h writes priced at 2x (cache v3)
- Transient account failures serve the last good value (bounded 30 min)
- Auto-refresh survives the sample-data toggle; ordered settings apply"
git push origin main
git push origin fix/deep-review-bug-batch
```

---

## Self-Review Notes

- **Spec coverage:** All 7 confirmed bugs map to Tasks 1–7; the single v3 bump (Task 4) covers the migration constraint. The "history preservation" concern resolves to: v2→v3 discard loses nothing beyond existing mirror-disk semantics (pruned files were already dropped every refresh); day-bucket tombstones remain future work (documented in review findings, not this batch).
- **Type consistency:** `cacheCreation1hTokens` (Tasks 4, 5), `refreshAccount(now:)` (Task 6), `accountStaleTTL` (Task 6) used consistently.
- **Ordering:** Task 3 (rates) precedes Task 5 (multiplier tests assume opus 5/25). Task 4 (field) precedes Task 5 (uses it).
