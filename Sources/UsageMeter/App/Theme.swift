import SwiftUI
import AppKit

// MARK: - Adaptive color plumbing

private extension NSColor {
    /// sRGB color from a 0xRRGGBB literal.
    convenience init(hex: UInt32) {
        self.init(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
                  green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255,
                  alpha: 1)
    }
}

extension Color {
    /// A dynamic color that resolves per-appearance — required because the app
    /// ships its own light/dark override (`AppAppearance`), so every semantic
    /// color needs an explicit pair instead of a single light-tuned value.
    init(light: UInt32, dark: UInt32) {
        self.init(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
                ? NSColor(hex: dark)
                : NSColor(hex: light)
        })
    }
}

// MARK: - Theme ("Kiln": teal interactive chrome + terracotta data ink)

/// Shared visual language. The identity is a duotone: everything you *click*
/// (buttons, links, tint, pickers) is deep teal; everything that *is data*
/// (chart bars, heatmap, the gauge brand mark) is fired terracotta. Chrome and
/// data never compete, and quota state escalates teal → amber → red — a ramp
/// that stays legible under deutan/protan color vision.
enum Theme {
    /// Interactive chrome: buttons, links, `.tint`, selection.
    static let accent = Color(light: 0x0F766E, dark: 0x2DD4BF)
    static let accentSoft = Color(light: 0xDDF0ED, dark: 0x11332F)

    /// Data ink: chart bars, heatmap, the gauge brand mark. Not for controls.
    static let data = Color(light: 0xC2410C, dark: 0xFB923C)
    /// De-emphasized companion to `data` — trend lines and context bars that
    /// must read as "same family, quieter" next to terracotta marks.
    static let dataMuted = Color(light: 0x9A6B4F, dark: 0xB08968)

    static let ok = Color(light: 0x277E42, dark: 0x4ADE80)
    static let warning = Color(light: 0x96690B, dark: 0xFBBF24)
    static let warningSoft = Color(light: 0xF6EDD4, dark: 0x3A2E0F)
    static let danger = Color(light: 0xB91C1C, dark: 0xF87171)
    /// Status-page "maintenance" state (slate blue, distinct from ok/warning).
    static let maintenance = Color(light: 0x3B6EA8, dark: 0x7FB0E8)

    /// Quota bar/track fill that escalates as a limit nears (CVD-safe ramp).
    static func usageColor(_ percent: Double) -> Color {
        switch percent {
        case 90...: return danger
        case 75..<90: return warning
        default: return accent
        }
    }

    /// Big % numerals stay calm (`.primary`) until the limit actually needs
    /// attention — color in numbers means "act", not "brand".
    static func numeralColor(_ percent: Double) -> Color {
        switch percent {
        case 90...: return danger
        case 75..<90: return warning
        default: return .primary
        }
    }

    /// Usage-history chart bar gradient (data ink).
    static let chartTop = Color(light: 0xE58F5E, dark: 0xFDAF74)
    static let chartBottom = Color(light: 0xC2410C, dark: 0xEA7A33)
    static var chartGradient: LinearGradient {
        LinearGradient(colors: [chartTop, chartBottom], startPoint: .top, endPoint: .bottom)
    }

    /// Opaque heatmap ramp (levels 1–4). Opaque on purpose: translucent accent
    /// steps shifted with the card behind them and vanished in dark mode.
    static let heat: [Color] = [
        Color(light: 0xF6E0D2, dark: 0x3E2415),
        Color(light: 0xECB088, dark: 0x6E3D1E),
        Color(light: 0xD0784A, dark: 0xB45E2C),
        Color(light: 0xA93E0F, dark: 0xFB923C)
    ]
    /// Empty heatmap cell / neutral inset fill — adapts with the system.
    static let heatEmpty = Color(nsColor: .quaternarySystemFill)

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

/// A capsule progress bar with an animated fill and 75/90% threshold ticks —
/// the ticks give the severity steps a non-color cue.
struct UsageBar: View {
    /// 0...100.
    let percent: Double
    var color: Color
    var height: CGFloat = 9
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.heatEmpty)
                Capsule()
                    .fill(color)
                    .frame(width: max(0, min(1, percent / 100)) * geo.size.width)
                    .animation(reduceMotion ? nil : .easeOut(duration: 0.55), value: percent)
                ForEach([0.75, 0.90], id: \.self) { threshold in
                    Rectangle()
                        .fill(.secondary.opacity(0.35))
                        .frame(width: 1.5)
                        .offset(x: threshold * geo.size.width)
                }
            }
            .clipShape(Capsule())
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

/// A rounded card with the native inset fill + hairline border, so edges hold
/// in both appearances (the old flat 5%-primary wash disappeared in dark mode).
struct CardBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(12)
            .background(
                Color(nsColor: .quaternarySystemFill),
                in: RoundedRectangle(cornerRadius: Theme.cardCorner, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cardCorner, style: .continuous)
                    .strokeBorder(Color(nsColor: .separatorColor).opacity(0.6), lineWidth: 1)
            )
    }
}

extension View {
    func card() -> some View { modifier(CardBackground()) }
}
