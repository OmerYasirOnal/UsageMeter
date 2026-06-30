import Foundation

/// The empirically-discovered usage endpoint, persisted so headless refreshes
/// survive relaunch without re-opening the login WebView.
public struct AccountEndpointInfo: Codable, Sendable, Equatable {
    /// Absolute usage endpoint URL discovered by the in-app capture.
    public var url: String
    /// HTTP method observed for the usage request (defaults to GET).
    public var method: String
    /// When it was discovered.
    public var capturedAt: Date?

    public init(url: String, method: String = "GET", capturedAt: Date? = nil) {
        self.url = url
        self.method = method
        self.capturedAt = capturedAt
    }

    public var resolvedURL: URL? { URL(string: url) }

    /// Absolute (scheme+host) and first-party — the only endpoints we'll replay
    /// session cookies to.
    public var isValidFirstParty: Bool {
        guard let resolved = resolvedURL, resolved.scheme != nil else { return false }
        return AccountHosts.isFirstParty(url: resolved)
    }
}

/// Persists `AccountEndpointInfo` as JSON.
///
/// `@unchecked Sendable`: only stored state is a thread-safe `FileManager`.
public struct AccountEndpointStore: @unchecked Sendable {
    public let fileURL: URL
    private let fileManager: FileManager

    public init(directory: URL? = nil, fileManager: FileManager = .default) {
        self.fileManager = fileManager
        let dir = directory ?? UsageStore.defaultDirectory(fileManager: fileManager)
        self.fileURL = dir.appendingPathComponent("account_endpoint.json", isDirectory: false)
    }

    public func load() -> AccountEndpointInfo? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(AccountEndpointInfo.self, from: data)
    }

    @discardableResult
    public func save(_ info: AccountEndpointInfo) -> Bool {
        do {
            try fileManager.createDirectory(at: fileURL.deletingLastPathComponent(),
                                            withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            try encoder.encode(info).write(to: fileURL, options: [.atomic])
            return true
        } catch {
            return false
        }
    }

    public func clear() {
        try? fileManager.removeItem(at: fileURL)
    }
}
