import SwiftUI
import UsageMeterKit

/// The menu-bar item: a gauge glyph; when logged in it shows the live account
/// session % (tinted by how close you are to the limit), otherwise optionally
/// today's Claude Code cost. Tint falls back to the service-status color.
///
/// Note: the menu-bar label is rendered by AppKit as a *template image*, which
/// only reliably reproduces `Text`/SF-Symbol `Image` — a live `Canvas` silently
/// drops out and breaks the layout. `MenuBarGaugeRenderer` sidesteps this by
/// pre-rendering the gauge to an `NSImage` (a real filling ring, not a static
/// glyph) instead of drawing it live.
struct MenuBarLabel: View {
    @ObservedObject var model: AppModel
    @Environment(\.openWindow) private var openWindow
    @State private var didAutoOpen = false

    var body: some View {
        HStack(spacing: 4) {
            if DemoData.isEnabled {
                Text("DEMO").font(.system(size: 10, weight: .bold, design: .rounded))
            }
            Image(nsImage: MenuBarGaugeRenderer.render(percent: model.snapshot.account?.session?.percent))
                .renderingMode(.template)
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
