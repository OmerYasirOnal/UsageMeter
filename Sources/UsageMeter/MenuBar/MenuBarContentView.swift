import SwiftUI
import AppKit
import UsageMeterKit

/// The popover shown when the menu-bar item is clicked.
struct MenuBarContentView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            // Account (Source A) — compiled out of the local-only App Store build.
            #if !APPSTORE
            if let account = model.snapshot.account, account.hasAnyMetric {
                if let banner = limitBanner(account) { banner }
                accountMetrics(account)
            } else {
                loggedOutAccount
            }
            Divider()
            #endif
            claudeCodeSection
            if let block = model.snapshot.claudeCode.activeBlock {
                blockSection(block)
            }
            Divider()
            footer
        }
        .padding(16)
        .frame(width: 340)
        .fixedSize(horizontal: false, vertical: true)
        .tint(Theme.accent)
        .preferredColorScheme(model.settings.appearance.colorScheme)
        // Keep the data live *while the popover is open*: refresh on appear, then
        // every 60s (the app's polite floor) until it closes. SwiftUI cancels this
        // task when the view disappears, so we never poll in the background here.
        .task {
            while !Task.isCancelled {
                await model.refresh()
                try? await Task.sleep(for: .seconds(AppSettings.minimumIntervalSeconds))
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 9) {
                Image(systemName: "gauge.with.dots.needle.50percent")
                    .font(.title3)
                    .foregroundStyle(Theme.accent)
                Text("UsageMeter").font(.headline)
                Spacer()
                iconButton("chart.bar.xaxis", help: "Open dashboard") { openDashboard() }
                iconButton("gearshape", help: "Settings") { openSettingsWindow() }
                if model.isRefreshing {
                    ProgressView()
                        .controlSize(.small)
                        .frame(width: 26, height: 26)
                } else {
                    iconButton("arrow.clockwise", help: "Refresh now") {
                        Task { await model.refresh() }
                    }
                }
            }
            HStack(spacing: 5) {
                Circle().fill(statusIndicator.color).frame(width: 7, height: 7)
                Text(model.snapshot.status?.description ?? "Status unavailable")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }

    private var statusIndicator: StatusIndicator {
        model.snapshot.status?.indicator ?? .unknown
    }

    // MARK: - Account (Source A)

    @ViewBuilder
    private func accountMetrics(_ account: AccountUsage) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                SectionLabel(text: "Account")
                Spacer()
                #if !APPSTORE
                Button("Log out") { Task { await model.logOut() } }
                    .buttonStyle(.borderless)
                    .font(.caption2)
                    .foregroundStyle(Theme.accent)
                #endif
            }
            if let session = account.session { accountMetric("Current Session", key: "Session", session) }
            if let weekly = account.weekly { accountMetric("Weekly Limit", key: "Weekly", weekly) }
            if let opus = account.weeklyOpus { accountMetric("Weekly Opus", key: "Weekly Opus", opus) }
            if let spend = account.spend {
                HStack {
                    Text("Pay-as-you-go used").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Text(Formatting.money(spend.usedAmount, currency: spend.currency))
                        .font(.callout.weight(.semibold)).monospacedDigit()
                }
            }
        }
    }

    private func accountMetric(_ title: String, key: String, _ metric: UsageMetric) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
            Text("\(metric.displayPercent)%")
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(Theme.usageColor(metric.percent))
                .contentTransition(.numericText())
                .animation(.snappy, value: metric.displayPercent)
            UsageBar(percent: metric.percent, color: Theme.usageColor(metric.percent))
            // Tick once a minute so the "Resets in 2h 8m" countdown and the burn
            // projection stay live while the popover is open.
            TimelineView(.periodic(from: .now, by: 60)) { context in
                VStack(alignment: .leading, spacing: 3) {
                    if let reset = Formatting.resetDescription(to: metric.resetsAt, now: context.date) {
                        Text("Resets \(reset)").font(.caption).foregroundStyle(.secondary)
                    }
                    projectionLine(model.projection(for: key, metric, now: context.date))
                }
            }
        }
    }

    /// "When will you run out" — the burn projection for one metric.
    @ViewBuilder
    private func projectionLine(_ proj: UsageProjection) -> some View {
        switch proj.status {
        case .exhausts(let ttl, _):
            Label("At this pace: hits the limit in ~\(Formatting.duration(ttl)) — before it resets",
                  systemImage: "exclamationmark.triangle.fill")
                .font(.caption2).foregroundStyle(Theme.warning)
                .fixedSize(horizontal: false, vertical: true)
        case .resetsFirst(let ttl):
            Label("On pace to reset before the limit (~\(Formatting.duration(ttl)) to limit)",
                  systemImage: "checkmark.circle")
                .font(.caption2).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        case .gathering, .notRising:
            EmptyView()
        }
    }

    @ViewBuilder
    private func limitBanner(_ account: AccountUsage) -> (some View)? {
        let peak = account.peakPercent
        if peak >= 75 {
            let nearest = [account.session, account.weekly, account.weeklyOpus]
                .compactMap { $0 }
                .max(by: { $0.percent < $1.percent })
            let resets = Formatting.resetDescription(to: nearest?.resetsAt)
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(Theme.warning)
                Text(peak >= 90
                     ? "You're close to a limit\(resets.map { " — resets \($0)" } ?? "")"
                     : "Approaching a limit\(resets.map { " — resets \($0)" } ?? "")")
                    .font(.caption)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(10)
            .background(Theme.warningSoft, in: RoundedRectangle(cornerRadius: Theme.corner, style: .continuous))
        }
    }

    private var loggedOutAccount: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(text: "Account")
            Button { openLogin() } label: {
                HStack(spacing: 8) {
                    Image(systemName: "person.crop.circle.badge.plus")
                    Text("Log in to claude.ai").fontWeight(.semibold)
                    Spacer()
                    Image(systemName: "chevron.right").font(.caption.weight(.semibold)).opacity(0.8)
                }
                .padding(.vertical, 9)
                .padding(.horizontal, 12)
                .frame(maxWidth: .infinity)
                .background(Theme.accent, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
            Text("See your live session & weekly % — local-only until you log in.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Claude Code (Source B)

    private var claudeCodeSection: some View {
        let cc = model.snapshot.claudeCode
        return VStack(alignment: .leading, spacing: 8) {
            SectionLabel(text: "Claude Code — Today")
            HStack {
                metric(title: "Tokens", value: Formatting.tokens(cc.today.totalTokens))
                Spacer()
                if model.settings.showApiValue {
                    metric(title: "API value", value: Formatting.cost(cc.todayEstimatedCost))
                }
            }
            if cc.recordCount == 0 {
                Text("No Claude Code usage yet. Run Claude Code, then refresh.")
                    .font(.caption2).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else if model.settings.showApiValue {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(cc.sessionCount) sessions · all-time ≈ \(Formatting.cost(cc.totalEstimatedCost))")
                    Text("“API value” isn’t money you’re billed — it’s what your tokens would cost at API rates.")
                }
                .font(.caption2).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("\(cc.sessionCount) sessions")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    private func blockSection(_ block: UsageBlock) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel(text: "Current 5-hour block (local estimate)")
            HStack {
                metric(title: "Tokens", value: Formatting.tokens(block.totalTokens))
                Spacer()
                TimelineView(.periodic(from: .now, by: 60)) { context in
                    if let resets = Formatting.countdown(to: block.end, now: context.date) {
                        metric(title: "Resets in", value: resets)
                    }
                }
            }
        }
    }

    // MARK: - Footer

    private var footer: some View {
        VStack(alignment: .leading, spacing: 10) {
            TimelineView(.periodic(from: .now, by: 60)) { context in
                // When logged in, "Updated" reflects the ACCOUNT fetch time (the % is
                // what the user cares about), not the local log scan (which never
                // fails and would always read "just now").
                let stamp = model.snapshot.account?.fetchedAt ?? model.snapshot.lastUpdated
                Text("Updated \(Formatting.relativeUpdated(stamp, now: context.date))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 8) {
                Button { openDashboard() } label: {
                    Label("Dashboard", systemImage: "chart.bar.xaxis")
                }
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }
            }
            .font(.callout)
            Text("Privacy: only token counts, model, and timestamps are read — never your messages.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Helpers

    private func iconButton(_ name: String, help: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: name)
                .font(.system(size: 13, weight: .medium))
                .frame(width: 26, height: 26)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .foregroundStyle(.secondary)
        .help(help)
    }

    private func metric(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value).font(.title3.weight(.semibold)).monospacedDigit()
            Text(title).font(.caption2).foregroundStyle(.secondary)
        }
    }

    private func openDashboard() {
        openWindow(id: AppWindowID.dashboard)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func openLogin() {
        openWindow(id: AppWindowID.accountLogin)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// In a menu-bar-only (accessory) app, `SettingsLink` can silently no-op
    /// because the app isn't active — activate first, then send the action.
    private func openSettingsWindow() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
    }
}
