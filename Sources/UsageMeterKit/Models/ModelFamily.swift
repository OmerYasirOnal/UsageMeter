import Foundation

/// A coarse model family used for pricing and grouping.
///
/// We deliberately match by substring on a lowercased identifier so that
/// every observed naming style maps correctly:
///   - full ids:   `claude-opus-4-8`, `claude-sonnet-4-6`, `claude-haiku-4-5-20251001`, `claude-fable-5`
///   - bare alias: `opus`, `sonnet`, `haiku`, `fable`, `mythos`
///   - synthetic / local / unknown ids → `.unknown` (cost reported as n/a)
public enum ModelFamily: String, Codable, Sendable, CaseIterable {
    case opus
    case sonnet
    case haiku
    case fable
    case mythos
    case unknown

    public init(modelIdentifier raw: String) {
        let id = raw.lowercased()
        // Order matters only in that each family token is distinct; substring match is enough.
        if id.contains("opus") {
            self = .opus
        } else if id.contains("sonnet") {
            self = .sonnet
        } else if id.contains("haiku") {
            self = .haiku
        } else if id.contains("fable") {
            self = .fable
        } else if id.contains("mythos") {
            self = .mythos
        } else {
            self = .unknown
        }
    }

    /// Whether we attempt a cost estimate for this family.
    /// Unknown families (incl. `<synthetic>` and local models) are reported as n/a.
    public var isPriced: Bool {
        self != .unknown
    }

    /// Human-friendly label for the UI.
    public var displayName: String {
        switch self {
        case .opus: return "Opus"
        case .sonnet: return "Sonnet"
        case .haiku: return "Haiku"
        case .fable: return "Fable"
        case .mythos: return "Mythos"
        case .unknown: return "Other"
        }
    }
}
