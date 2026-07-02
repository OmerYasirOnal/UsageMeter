import Foundation

/// Source B behind a protocol — mirroring `StatusClient` (C) and
/// `AccountUsageClient` (A) so all three sources are decoupled and mockable
/// (Section 8: "decouple the three sources behind protocols").
///
/// Implementations own their incremental cache; `DataEngine` just asks for stats.
public protocol ClaudeCodeSource: Sendable {
    /// Stats from whatever is already cached (cheap; no disk scan). For launch.
    func cachedStats(now: Date) -> ClaudeCodeStats
    /// Incrementally rescan the given roots and return fresh stats.
    func refresh(roots: [URL], now: Date) -> ClaudeCodeStats
    /// Drop all cached data.
    func reset()
    /// When the cache was last refreshed (nil if never).
    var lastUpdated: Date? { get }
}

/// The real implementation: scan → parse → aggregate over `~/.claude/projects`,
/// with an incremental Codable cache (unchanged files are never re-read).
///
/// `@unchecked Sendable`: it holds mutable cache state, but it is only ever
/// touched from inside the `DataEngine` actor, which serializes all access.
public final class LocalClaudeCodeSource: ClaudeCodeSource, @unchecked Sendable {
    private let store: UsageStore
    private let scanner: ProjectScanner
    private let parser: JSONLParser
    private let aggregator: DailyAggregator
    private var cache: CacheData

    public init(
        store: UsageStore = UsageStore(),
        pricing: Pricing = .defaults,
        calendar: Calendar = .current
    ) {
        self.store = store
        self.scanner = ProjectScanner()
        self.parser = JSONLParser()
        self.aggregator = DailyAggregator(calculator: CostCalculator(pricing: pricing), calendar: calendar)
        self.cache = store.load()
    }

    public var lastUpdated: Date? { cache.lastUpdated }

    public func cachedStats(now: Date) -> ClaudeCodeStats {
        aggregate(now: now)
    }

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

        // Unchanged files keep their cached records. Save only on real changes —
        // an unconditional save would be a full multi-MB rewrite every tick.
        cache.lastUpdated = now
        store.save(cache)
        return aggregate(now: now)
    }

    public func reset() {
        store.clear()
        cache = .empty
    }

    private func aggregate(now: Date) -> ClaudeCodeStats {
        // Session counts come from the discovered files (via stored projectID),
        // so even zero-record session files are counted per project.
        var sessionCountByProject: [String: Int] = [:]
        for cached in cache.files.values {
            sessionCountByProject[cached.projectID, default: 0] += 1
        }
        return aggregator.aggregate(
            records: cache.allRecords,
            now: now,
            sessionCountByProject: sessionCountByProject,
            totalSessions: cache.files.count
        )
    }
}
