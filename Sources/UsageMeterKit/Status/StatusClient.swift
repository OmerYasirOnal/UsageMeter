import Foundation

/// Source C — service status. Behind a protocol so it is trivially mockable and
/// the rest of the app is decoupled from the network.
public protocol StatusClient: Sendable {
    func fetch() async throws -> ServiceStatus
}

/// Pure decoder for the Atlassian Statuspage `summary.json` shape. Kept separate
/// from the network so it is unit-testable with a fixture (no live calls).
public enum StatusDecoder {
    /// Raw shape — only the fields we surface; everything else is ignored.
    private struct Summary: Decodable {
        struct Status: Decodable {
            let indicator: String?
            let description: String?
        }
        struct Incident: Decodable {
            let id: String
            let name: String
            let status: String?
            let impact: String?
            let shortlink: String?
        }
        let status: Status?
        let incidents: [Incident]?
        let scheduled_maintenances: [Incident]?
    }

    public static func decodeSummary(_ data: Data, fetchedAt: Date? = nil) throws -> ServiceStatus {
        let summary = try JSONDecoder().decode(Summary.self, from: data)
        let indicator = StatusIndicator(rawValueDefaulting: summary.status?.indicator)
        let description = summary.status?.description ?? "Status unknown"
        let incidents = (summary.incidents ?? []).map {
            IncidentSummary(id: $0.id, name: $0.name, status: $0.status ?? "",
                            impact: $0.impact, shortlink: $0.shortlink)
        }
        let maintenances = (summary.scheduled_maintenances ?? []).map {
            IncidentSummary(id: $0.id, name: $0.name, status: $0.status ?? "",
                            impact: $0.impact, shortlink: $0.shortlink)
        }
        return ServiceStatus(
            indicator: indicator,
            description: description,
            incidents: incidents,
            scheduledMaintenances: maintenances,
            fetchedAt: fetchedAt
        )
    }
}

/// Live implementation polling Anthropic's public Statuspage JSON (no auth).
public struct LiveStatusClient: StatusClient {
    public static let defaultURL = URL(string: "https://status.claude.com/api/v2/summary.json")!

    private let url: URL
    private let session: URLSession

    public init(url: URL = LiveStatusClient.defaultURL, session: URLSession = .shared) {
        self.url = url
        self.session = session
    }

    public func fetch() async throws -> ServiceStatus {
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("UsageMeter/1.0 (+https://github.com)", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw StatusClientError.badStatus(http.statusCode)
        }
        return try StatusDecoder.decodeSummary(data, fetchedAt: Date())
    }
}

public enum StatusClientError: Error, Sendable, Equatable {
    case badStatus(Int)
}

/// A static stand-in used in previews/tests.
public struct StubStatusClient: StatusClient {
    private let result: Result<ServiceStatus, StatusClientErrorBox>

    public init(_ status: ServiceStatus) { self.result = .success(status) }
    public init(error: Error) { self.result = .failure(StatusClientErrorBox(error)) }

    public func fetch() async throws -> ServiceStatus {
        switch result {
        case .success(let status): return status
        case .failure(let box): throw box.error
        }
    }
}

/// Allows wrapping an arbitrary error in a Sendable box for the stub.
public struct StatusClientErrorBox: Error, @unchecked Sendable {
    public let error: Error
    public init(_ error: Error) { self.error = error }
}
