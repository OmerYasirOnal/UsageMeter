import Foundation

/// One cached session file: its fingerprint, the owning project, plus the
/// privacy-safe records parsed from it. Caching parsed records (not raw lines) is
/// what makes re-scans incremental — unchanged files are never re-read. Storing
/// `projectID` here means even zero-record session files are counted per project.
public struct CachedFile: Codable, Sendable, Equatable {
    public var stamp: FileStamp
    public var projectID: String
    public var records: [UsageRecord]

    public init(stamp: FileStamp, projectID: String, records: [UsageRecord]) {
        self.stamp = stamp
        self.projectID = projectID
        self.records = records
    }
}

/// The Source-B on-disk cache (Codable; GRDB/SQLite is a planned M3 upgrade for
/// large histories — see README for the rationale). It holds ONLY local Claude
/// Code data (paths, fingerprints, token records) — never message content. The
/// service status (Source C) has its own `StatusStore`, keeping the sources
/// decoupled in persistence too.
public struct CacheData: Codable, Sendable, Equatable {
    /// v3: `TokenUsage` gained `cacheCreation1hTokens` (cache_creation TTL split);
    /// bumping forces one full re-parse so existing records pick up 1h data.
    public static let currentVersion = 3

    public var version: Int
    /// path -> cached file.
    public var files: [String: CachedFile]
    /// When the cache was last refreshed.
    public var lastUpdated: Date?

    public init(
        version: Int = CacheData.currentVersion,
        files: [String: CachedFile] = [:],
        lastUpdated: Date? = nil
    ) {
        self.version = version
        self.files = files
        self.lastUpdated = lastUpdated
    }

    public static let empty = CacheData()

    /// Path -> fingerprint view used by `ProjectScanner.diff`.
    public var stamps: [String: FileStamp] {
        files.mapValues { $0.stamp }
    }

    /// All cached records across every file (input to the aggregator).
    public var allRecords: [UsageRecord] {
        files.values.flatMap { $0.records }
    }
}

/// Loads/saves the cache as JSON. Pure file IO; the `DataEngine` actor owns the
/// single instance so there is no concurrent access.
///
/// `@unchecked Sendable`: the only stored state is a thread-safe `FileManager`.
public struct UsageStore: @unchecked Sendable {
    public let fileURL: URL
    private let fileManager: FileManager

    /// - Parameter directory: where to keep `cache.json`. Defaults to
    ///   `~/Library/Application Support/UsageMeter`. Tests inject a temp dir.
    public init(directory: URL? = nil, fileManager: FileManager = .default) {
        self.fileManager = fileManager
        let dir = directory ?? UsageStore.defaultDirectory(fileManager: fileManager)
        self.fileURL = dir.appendingPathComponent("cache.json", isDirectory: false)
    }

    public static func defaultDirectory(fileManager: FileManager = .default) -> URL {
        let base = (try? fileManager.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                         appropriateFor: nil, create: true))
            ?? fileManager.temporaryDirectory
        return base.appendingPathComponent("UsageMeter", isDirectory: true)
    }

    /// Load the cache, returning `.empty` on any failure (missing/corrupt/old version).
    public func load() -> CacheData {
        guard let data = try? Data(contentsOf: fileURL) else { return .empty }
        guard let cache = try? JSONDecoder.cacheDecoder.decode(CacheData.self, from: data) else {
            return .empty
        }
        guard cache.version == CacheData.currentVersion else { return .empty }
        return cache
    }

    /// Atomically persist the cache. Failures are swallowed (cache is best-effort).
    @discardableResult
    public func save(_ cache: CacheData) -> Bool {
        do {
            try fileManager.createDirectory(at: fileURL.deletingLastPathComponent(),
                                            withIntermediateDirectories: true)
            let data = try JSONEncoder.cacheEncoder.encode(cache)
            try data.write(to: fileURL, options: [.atomic])
            return true
        } catch {
            return false
        }
    }

    /// Remove the cache file (used by a future "reset" action).
    public func clear() {
        try? fileManager.removeItem(at: fileURL)
    }
}

private extension JSONEncoder {
    static let cacheEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()
}

private extension JSONDecoder {
    static let cacheDecoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
