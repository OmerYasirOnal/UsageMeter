import SwiftUI
import UsageMeterKit

/// The menu-bar item: a gauge glyph; when logged in it shows the live account
/// session % (tinted by how close you are to the limit), otherwise optionally
/// today's Claude Code cost. Tint falls back to the service-status color.
struct MenuBarLabel: View {
    @ObservedObject var model: AppModel
    @Environment(\.openWindow) private var openWindow
    @State private var didAutoOpen = false

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "gauge.with.dots.needle.50percent")
            if let session = model.snapshot.account?.session {
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
