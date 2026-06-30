import Foundation

/// Persists the last-good service status (Source C) so the popover can show
/// something instantly on launch / when offline. Kept separate from the Claude
/// Code cache so the three sources stay decoupled in persistence as well as code.
///
/// `@unchecked Sendable`: only stored state is a thread-safe `FileManager`.
public struct StatusStore: @unchecked Sendable {
    public let fileURL: URL
    private let fileManager: FileManager

    public init(directory: URL? = nil, fileManager: FileManager = .default) {
        self.fileManager = fileManager
        let dir = directory ?? UsageStore.defaultDirectory(fileManager: fileManager)
        self.fileURL = dir.appendingPathComponent("status.json", isDirectory: false)
    }

    public func load() -> ServiceStatus? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(ServiceStatus.self, from: data)
    }

    @discardableResult
    public func save(_ status: ServiceStatus) -> Bool {
        do {
            try fileManager.createDirectory(at: fileURL.deletingLastPathComponent(),
                                            withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(status)
            try data.write(to: fileURL, options: [.atomic])
            return true
        } catch {
            return false
        }
    }

    public func clear() {
        try? fileManager.removeItem(at: fileURL)
    }
}
