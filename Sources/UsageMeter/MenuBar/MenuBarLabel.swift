import SwiftUI
import UsageMeterKit

/// The menu-bar item: a gauge glyph; when logged in it shows the live account
/// session % (tinted by how close you are to the limit), otherwise optionally
/// today's Claude Code cost. Tint falls back to the service-status color.
///
/// Note: the menu-bar label is rendered by AppKit as a *template image*, which
/// only reliably reproduces `Text`/SF-Symbol `Image` — custom `Canvas` drawing
/// (our `GaugeGlyph`) silently drops out and breaks the layout, so the menu bar
/// uses the SF Symbol gauge (same family as the app icon). `GaugeGlyph` is used
/// where it renders correctly: the app icon and the popover header (a real window).
struct MenuBarLabel: View {
    @ObservedObject var model: AppModel
    @Environment(\.openWindow) private var openWindow
    @State private var didAutoOpen = false

    var body: some View {
        HStack(spacing: 4) {
            if DemoData.isEnabled {
                Text("DEMO").font(.system(size: 10, weight: .bold, design: .rounded))
            }
            Image(systemName: "gauge.with.dots.needle.50percent")
            if model.settings.showPercentInMenuBar, let session = model.snapshot.account?.session {
                Text("\(session.displayPercent)%").monospacedDigit()
            } else if model.settings.showCostInMenuBar {
                Text(Formatting.cost(model.snapshot.claudeCode.todayEstimatedCost))
            }
        }
        .foregroundStyle(tint)
        .onAppear {
            // Self-test hook: open the login window on launch when requested.
            if !didAutoOpen, ProcessInfo.processInfo.environment["USAGEMETER_OPEN_LOGIN"] == "1" {
                didAutoOpen = true
                openWindow(id: AppWindowID.accountLogin)
            }
        }
    }

    private var tint: Color {
        if let session = model.snapshot.account?.session {
            return Theme.usageColor(session.percent)
        }
        return model.snapshot.status?.indicator.color ?? .primary
    }
}
