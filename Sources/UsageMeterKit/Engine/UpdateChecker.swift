import Foundation

/// Checks GitHub for a newer release of the direct-download build. One
/// anonymous GET to the public releases API, at most once per `minInterval`;
/// never runs in the App Store build (updates flow through the store there).
/// Fails safe: any parse/network oddity means "no update", never a false prompt.
public struct UpdateChecker: Sendable {
    public struct Release: Equatable, Sendable {
        public let version: String   // normalized, no leading "v"
        public let url: URL

        public init(version: String, url: URL) {
            self.version = version
            self.url = url
        }
    }

    public static let defaultEndpoint =
        URL(string: "https://api.github.com/repos/OmerYasirOnal/UsageMeter/releases/latest")!
    public static let minInterval: TimeInterval = 24 * 60 * 60

    private let endpoint: URL
    private let urlSession: URLSession

    public init(endpoint: URL = UpdateChecker.defaultEndpoint, urlSession: URLSession = .shared) {
        self.endpoint = endpoint
        self.urlSession = urlSession
    }

    /// The newest stable release, or nil (also on any failure).
    public func latestRelease() async -> Release? {
        var request = URLRequest(url: endpoint)
        request.timeoutInterval = 15
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("UsageMeter", forHTTPHeaderField: "User-Agent")
        guard let (data, response) = try? await urlSession.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return Self.decodeLatest(data)
    }

    // MARK: - Pure helpers (unit-tested)

    static func decodeLatest(_ data: Data) -> Release? {
        struct Payload: Decodable {
            let tag_name: String
            let html_url: String
            let draft: Bool
            let prerelease: Bool
        }
        guard let payload = try? JSONDecoder().decode(Payload.self, from: data),
              !payload.draft, !payload.prerelease,
              let url = URL(string: payload.html_url) else { return nil }
        return Release(version: normalize(payload.tag_name), url: url)
    }

    static func normalize(_ tag: String) -> String {
        tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
    }

    /// Strict numeric semver-ish comparison; non-numeric input is never "newer".
    public static func isNewer(_ candidate: String, than current: String) -> Bool {
        let a = components(normalize(candidate)), b = components(normalize(current))
        guard let a, let b else { return false }
        for i in 0..<max(a.count, b.count) {
            let x = i < a.count ? a[i] : 0
            let y = i < b.count ? b[i] : 0
            if x != y { return x > y }
        }
        return false
    }

    private static func components(_ version: String) -> [Int]? {
        let parts = version.split(separator: ".").map { Int($0) }
        guard !parts.isEmpty, parts.allSatisfy({ $0 != nil }) else { return nil }
        return parts.compactMap { $0 }
    }
}
