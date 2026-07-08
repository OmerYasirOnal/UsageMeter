import SwiftUI
import UsageMeterKit

/// The menu-bar item: a gauge glyph whose needle/fill tracks the live account
/// session % (tinted by how close you are to the limit), otherwise optionally
/// today's Claude Code cost. Tint falls back to the service-status color.
///
/// Note: the menu-bar label is rendered by AppKit as a *template image*, which
/// only reliably reproduces `Text`/SF-Symbol `Image` — custom `Canvas` drawing
/// (our old `GaugeGlyph`) silently drops out and breaks the layout, so the menu
/// bar can't paint a live custom fill shape. Instead it picks between the SF
/// Symbol gauge family's discrete needle positions (`0/33/50/67/100percent`,
/// same family as the app icon) so the glyph's filled arc genuinely narrows/
/// widens with usage, with a `.replace` symbol transition on change — all
/// while staying template-image-safe. Custom `Canvas` drawing is used only
/// where it renders correctly: the app icon.
struct MenuBarLabel: View {
    @ObservedObject var model: AppModel
    @Environment(\.openWindow) private var openWindow
    @State private var didAutoOpen = false

    var body: some View {
        HStack(spacing: 3) {
            if DemoData.isEnabled {
                Text("DEMO").font(.system(size: 10, weight: .bold, design: .rounded))
            }
            Image(systemName: gaugeSymbolName)
                .contentTransition(.symbolEffect(.replace))
                .animation(.bouncy(duration: 0.35), value: gaugeSymbolName)
            if model.settings.showPercentInMenuBar, let session = model.snapshot.account?.session {
                Text("\(session.displayPercent)%").monospacedDigit()
            } else if model.settings.showCostInMenuBar,
                      let today = model.snapshot.claudeCode.todayEstimatedCost {
                // Compact + monospaced so the status item doesn't change width
                // every refresh and nudge neighboring icons.
                Text(Formatting.menuBarCost(today)).monospacedDigit()
            }
        }
        .foregroundStyle(tint)
        .onAppear {
            // Self-test / screenshot hooks: open a window on launch when requested.
            #if !APPSTORE
            if !didAutoOpen, ProcessInfo.processInfo.environment["USAGEMETER_OPEN_LOGIN"] == "1" {
                didAutoOpen = true
                openWindow(id: AppWindowID.accountLogin)
            }
            #endif
            if !didAutoOpen, ProcessInfo.processInfo.environment["USAGEMETER_OPEN_DASHBOARD"] == "1" {
                didAutoOpen = true
                openWindow(id: AppWindowID.dashboard)
            }
        }
    }

    /// Picks the SF Symbol gauge variant whose needle sits closest to the real
    /// session %, so the glyph itself — not just the text next to it — reflects
    /// usage level. Bucket edges sit at the midpoints between the symbol
    /// family's five stops. Falls back to the neutral "50percent" dial when no
    /// live % is known yet (local-only mode / logged out) — same as before.
    private var gaugeSymbolName: String {
        guard let percent = model.snapshot.account?.session?.displayPercent else {
            return "gauge.with.dots.needle.50percent"
        }
        switch percent {
        case ..<17: return "gauge.with.dots.needle.0percent"
        case 17..<42: return "gauge.with.dots.needle.33percent"
        case 42..<59: return "gauge.with.dots.needle.50percent"
        case 59..<84: return "gauge.with.dots.needle.67percent"
        default: return "gauge.with.dots.needle.100percent"
        }
    }

    /// Menu-bar color means "act now": template-neutral all day, warning/danger
    /// only when the session limit nears, status color only during an incident.
    /// A permanently-colored item clashes with neighboring template icons and
    /// trains the eye to ignore it.
    private var tint: Color {
        if let session = model.snapshot.account?.session {
            if session.percent >= 90 { return Theme.danger }
            if session.percent >= 75 { return Theme.warning }
        }
        switch model.snapshot.status?.indicator {
        case .minor?, .major?, .critical?:
            return model.snapshot.status?.indicator.color ?? .primary
        default:
            return .primary
        }
    }
}
