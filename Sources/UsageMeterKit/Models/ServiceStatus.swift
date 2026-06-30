import Foundation

/// Overall service health indicator (mirrors Atlassian Statuspage `status.indicator`).
public enum StatusIndicator: String, Codable, Sendable, CaseIterable {
    case none        // "All Systems Operational"
    case minor
    case major
    case critical
    case maintenance
    case unknown

    public init(rawValueDefaulting raw: String?) {
        guard let raw, let value = StatusIndicator(rawValue: raw.lowercased()) else {
            self = .unknown
            return
        }
        self = value
    }

    /// Whether everything is nominal.
    public var isOperational: Bool { self == .none }
}

/// One unresolved incident or scheduled maintenance, distilled for the badge UI.
public struct IncidentSummary: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var name: String
    public var status: String
    public var impact: String?
    public var shortlink: String?

    public init(id: String, name: String, status: String, impact: String? = nil, shortlink: String? = nil) {
        self.id = id
        self.name = name
        self.status = status
        self.impact = impact
        self.shortlink = shortlink
    }
}

/// The distilled service status the UI consumes (Source C).
public struct ServiceStatus: Codable, Sendable, Equatable {
    public var indicator: StatusIndicator
    public var description: String
    public var incidents: [IncidentSummary]
    public var scheduledMaintenances: [IncidentSummary]
    public var fetchedAt: Date?

    public init(
        indicator: StatusIndicator,
        description: String,
        incidents: [IncidentSummary] = [],
        scheduledMaintenances: [IncidentSummary] = [],
        fetchedAt: Date? = nil
    ) {
        self.indicator = indicator
        self.description = description
        self.incidents = incidents
        self.scheduledMaintenances = scheduledMaintenances
        self.fetchedAt = fetchedAt
    }

    /// Whether there is anything noteworthy to surface to the user.
    public var hasActiveIssues: Bool {
        !indicator.isOperational || !incidents.isEmpty
    }
}
