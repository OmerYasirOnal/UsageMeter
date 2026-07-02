import SwiftUI
import UsageMeterKit

extension StatusIndicator {
    /// Dot color for the status badge — mapped through Theme so the whole app
    /// shares one semantic scale (and a palette swap stays a one-file change).
    var color: Color {
        switch self {
        case .none: return Theme.ok
        case .minor: return Theme.warning
        case .major: return Theme.data
        case .critical: return Theme.danger
        case .maintenance: return Theme.maintenance
        case .unknown: return .secondary
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
