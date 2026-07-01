import SwiftUI

/// Shared visual language so the menu-bar popover, settings, and dashboard look
/// like one cohesive product. Claude-inspired warm coral accent.
enum Theme {
    /// Primary brand accent (~Claude coral #D97757).
    static let accent = Color(red: 0.851, green: 0.467, blue: 0.341)
    static let accentSoft = Color(red: 0.851, green: 0.467, blue: 0.341).opacity(0.16)

    static let warning = Color(red: 0.85, green: 0.62, blue: 0.12)
    static let warningSoft = Color(red: 0.85, green: 0.62, blue: 0.12).opacity(0.16)
    static let danger = Color(red: 0.86, green: 0.27, blue: 0.22)
    static let ok = Color(red: 0.30, green: 0.72, blue: 0.42)

    /// Usage bar / percentage color that warms toward red as a limit nears.
    static func usageColor(_ percent: Double) -> Color {
        switch percent {
        case 90...: return danger
        case 75..<90: return Color(red: 0.92, green: 0.52, blue: 0.18)
        default: return accent
        }
    }

    static let corner: CGFloat = 12
    static let cardCorner: CGFloat = 14
}

/// User-selectable appearance (M3 deliverable).
enum AppAppearance: String, CaseIterable, Equatable {
    case system, light, dark

    var label: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

/// A capsule progress bar with an animated fill.
struct UsageBar: View {
    /// 0...100.
    let percent: Double
    var color: Color
    var height: CGFloat = 9

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(color.opacity(0.18))
                Capsule()
                    .fill(color)
                    .frame(width: max(0, min(1, percent / 100)) * geo.size.width)
                    .animation(.easeOut(duration: 0.55), value: percent)
            }
        }
        .frame(height: height)
        .accessibilityLabel("\(Int(percent.rounded())) percent used")
    }
}

/// A section header label, uppercased + tracked, matching the product style.
struct SectionLabel: View {
    let text: String
    var body: some View {
        Text(text.uppercased())
            .font(.caption2.weight(.semibold))
            .tracking(0.6)
            .foregroundStyle(.secondary)
    }
}

/// A small, unmistakable banner shown wherever sample/preview data is displayed,
/// so synthetic numbers can never be mistaken for real usage. Callers gate it on
/// `DemoData.isEnabled`.
struct SampleDataBanner: View {
    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: "wand.and.stars")
            Text("Sample data — for preview only")
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .font(.caption.weight(.medium))
        .foregroundStyle(Theme.accent)
        .padding(.vertical, 7)
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.accentSoft, in: RoundedRectangle(cornerRadius: Theme.corner, style: .continuous))
        .accessibilityLabel("Sample data, for preview only")
    }
}

/// A subtle rounded card container used across surfaces.
struct CardBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: Theme.cardCorner, style: .continuous)
                    .fill(Color.primary.opacity(0.05))
            )
    }
}

extension View {
    func card() -> some View { modifier(CardBackground()) }
}
