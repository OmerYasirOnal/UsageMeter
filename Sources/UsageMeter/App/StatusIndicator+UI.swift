import SwiftUI
import UsageMeterKit

extension StatusIndicator {
    /// Dot color for the status badge.
    var color: Color {
        switch self {
        case .none: return .green
        case .minor: return .yellow
        case .major: return .orange
        case .critical: return .red
        case .maintenance: return .blue
        case .unknown: return .gray
        }
    }

    /// Short label for compact UI.
    var shortLabel: String {
        switch self {
        case .none: return "Operational"
        case .minor: return "Minor issue"
        case .major: return "Major issue"
        case .critical: return "Critical"
        case .maintenance: return "Maintenance"
        case .unknown: return "Unknown"
        }
    }
}
