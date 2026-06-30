import Foundation

/// One de-duplicatable Claude Code usage event, distilled to the privacy-safe minimum.
///
/// This is the *only* shape we persist from Source B. It contains no message
/// content — just the usage counts, the model string, a timestamp, the dedup id,
/// and the project it belongs to.
public struct UsageRecord: Codable, Sendable, Equatable, Hashable {
    /// Dedup identity: `requestId` when present, otherwise `uuid`.
    public let id: String
    /// Raw model identifier as written by Claude Code (e.g. `claude-opus-4-8`).
    public let model: String
    /// Event timestamp (parsed from ISO-8601).
    public let timestamp: Date
    /// Token counts.
    public let usage: TokenUsage
    /// Project slug (the `~/.claude/projects/<slug>` folder name).
    public let projectID: String

    public init(
        id: String,
        model: String,
        timestamp: Date,
        usage: TokenUsage,
        projectID: String
    ) {
        self.id = id
        self.model = model
        self.timestamp = timestamp
        self.usage = usage
        self.projectID = projectID
    }

    public var family: ModelFamily { ModelFamily(modelIdentifier: model) }
}
