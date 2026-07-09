import SwiftUI
import AppKit
import UsageMeterKit

/// The popover shown when the menu-bar item is clicked.
///
/// Hierarchy is built for a 2-second glance: ONE hero (Current Session % with a
/// big reset countdown), compact rows for the slow-moving weekly limits, then
/// today's Claude Code numbers. Static/educational copy lives in tooltips and
/// Settings, not on the glance surface.
struct MenuBarContentView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var folderGranted = ClaudeFolderAccess.isGranted

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            if DemoData.isEnabled { SampleDataBanner() }
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
            // The 5-hour block IS the session window — showing both duplicates
            // the countdown. Keep it as the session proxy when there's no
            // account metric (local-only build / logged out).
            if model.snapshot.account?.session == nil,
               let block = model.snapshot.claudeCode.activeBlock {
                blockSection(block)
            }
            Divider()
            footer
        }
        .padding(16)
        .frame(width: 340)
        .fixedSize(horizontal: false, vertical: true)
        .tint(Theme.accent)
        // Esc closes the popover, like every native menu-bar window.
        .background(
            Button("") { dismiss() }
                .keyboardShortcut(.cancelAction)
                .opacity(0)
                .accessibilityHidden(true)
        )
        // Keep the data live *while the popover is open*: refresh on appear, then
        // every 60s (the app's polite floor) until it closes. SwiftUI cancels this
        // task when the view disappears, so we never poll in the background here.
        .task {
            while !Task.isCancelled {
                await model.refresh()
                try? await Task.sleep(for: .seconds(AppSettings.minimumIntervalSeconds))
            }
        }
        .onAppear { folderGranted = ClaudeFolderAccess.isGranted }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "gauge.with.dots.needle.50percent")
                .font(.title3)
                .foregroundStyle(Theme.data)
            Text("UsageMeter").font(.headline)
            // Status collapses to a dot; the text row appears only during an
            // incident (see below) — "Operational" doesn't need words.
            Circle()
                .fill(statusIndicator.color)
                .frame(width: 7, height: 7)
                .help(model.snapshot.status?.description ?? "Status unavailable")
                .accessibilityLabel("Claude status: \(statusIndicator.shortLabel)")
            Spacer()
            iconButton("gearshape", help: "Settings (⌘,)") { openSettingsWindow() }
                .keyboardShortcut(",", modifiers: .command)
            if model.isRefreshing {
                ProgressView()
                    .controlSize(.small)
                    .frame(width: 26, height: 26)
            } else {
                iconButton("arrow.clockwise", help: "Refresh now (⌘R)") {
                    Task { await model.refresh() }
                }
                .keyboardShortcut("r", modifiers: .command)
            }
        }
    }

    /// Incident banner row — only when something is actually wrong.
    @ViewBuilder
    private var statusIncidentRow: some View {
        if statusIndicator != .none && statusIndicator != .unknown {
            HStack(spacing: 5) {
                Circle().fill(statusIndicator.color).frame(width: 7, height: 7)
                Text(model.snapshot.status?.description ?? statusIndicator.shortLabel)
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
                statusIncidentRow
                #if !APPSTORE
                Button("Log out") { Task { await model.logOut() } }
                    .buttonStyle(.borderless)
                    .font(.caption2)
                    .foregroundStyle(Theme.accent)
                #endif
            }
            if let session = account.session { sessionHero(session) }
            if let weekly = account.weekly { compactMetric("Weekly Limit", key: "Weekly", weekly) }
            if let opus = account.weeklyOpus { compactMetric("Weekly Opus", key: "Weekly Opus", opus) }
            if let spend = account.spend, spend.usedAmount > 0 {
                HStack {
                    Text("Pay-as-you-go used").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Text(Formatting.money(spend.usedAmount, currency: spend.currency))
                        .font(.callout.weight(.semibold)).monospacedDigit()
                }
            }
        }
    }

    /// The ONE hero: session % + a countdown you can read across the room.
    /// "When do I get budget back" is the question — it gets hero billing too.
    private func sessionHero(_ metric: UsageMetric) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Current Session").font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
            TimelineView(.periodic(from: .now, by: 60)) { context in
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("\(metric.displayPercent)%")
                            .font(.system(size: 30, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(Theme.numeralColor(metric.percent))
                            .contentTransition(reduceMotion ? .identity : .numericText())
                            .animation(reduceMotion ? nil : .snappy, value: metric.displayPercent)
                        Spacer()
                        if let resetsAt = metric.resetsAt,
                           let cd = Formatting.countdown(to: resetsAt, now: context.date) {
                            VStack(alignment: .trailing, spacing: 1) {
                                Text(cd)
                                    .font(.title3.weight(.semibold)).monospacedDigit()
                                Text("until reset (\(Formatting.clockTime(resetsAt)))")
                                    .font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                    }
                    UsageBar(percent: metric.percent, color: Theme.usageColor(metric.percent))
                    projectionLine(model.projection(for: "Session", metric, now: context.date))
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Current session")
        .accessibilityValue(accessibilityMetricValue(metric))
    }

    /// Weekly limits move slowly — one compact line each, escalation only.
    private func compactMetric(_ title: String, key: String, _ metric: UsageMetric) -> some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(title).font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
                    Spacer()
                    if let reset = Formatting.resetDescription(to: metric.resetsAt, now: context.date) {
                        Text("resets \(reset)").font(.caption2).foregroundStyle(.tertiary)
                    }
                    Text("\(metric.displayPercent)%")
                        .font(.callout.weight(.semibold)).monospacedDigit()
                        .foregroundStyle(Theme.numeralColor(metric.percent))
                }
                UsageBar(percent: metric.percent, color: Theme.usageColor(metric.percent), height: 5)
                // Compact rows surface the projection only when it's a warning.
                if case .exhausts = model.projection(for: key, metric, now: context.date).status {
                    projectionLine(model.projection(for: key, metric, now: context.date))
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(accessibilityMetricValue(metric))
    }

    private func accessibilityMetricValue(_ metric: UsageMetric) -> String {
        var value = "\(metric.displayPercent) percent used"
        if let reset = Formatting.resetDescription(to: metric.resetsAt) {
            value += ", resets \(reset)"
        }
        return value
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
            HStack {
                SectionLabel(text: "Account")
                Spacer()
                statusIncidentRow
            }
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
            HStack {
                SectionLabel(text: "Claude Code — Today")
                Spacer()
                #if APPSTORE
                statusIncidentRow
                #endif
            }
            metric(title: "Tokens", value: Formatting.tokens(cc.today.totalTokens))
            if cc.recordCount == 0 {
                emptyState
            } else {
                Text("\(cc.sessionCount) sessions · all-time ≈ \(Formatting.tokens(cc.total.totalTokens))")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    /// First-run guidance. Ordered: still scanning → (App Store) missing sandbox
    /// grant → genuinely no usage. The grant CTA is the fix for the "empty app
    /// with no path forward" dead end in the sandboxed build.
    @ViewBuilder
    private var emptyState: some View {
        if !model.hasLoadedOnce {
            Text("Scanning session logs…")
                .font(.caption2).foregroundStyle(.secondary)
        } else {
            #if APPSTORE
            if !folderGranted {
                VStack(alignment: .leading, spacing: 6) {
                    Text("UsageMeter needs permission to read your Claude Code session logs (token counts only — never messages).")
                        .font(.caption2).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Button {
                        Task {
                            await model.grantClaudeFolderAccess()
                            folderGranted = ClaudeFolderAccess.isGranted
                        }
                    } label: {
                        Label("Grant access to ~/.claude…", systemImage: "folder.badge.plus")
                    }
                }
            } else {
                noUsageYet
            }
            #else
            noUsageYet
            #endif
        }
    }

    private var noUsageYet: some View {
        Text("No Claude Code usage yet. Run Claude Code, then refresh.")
            .font(.caption2).foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func blockSection(_ block: UsageBlock) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 4) {
                SectionLabel(text: "Current 5-hour block")
                Image(systemName: "info.circle")
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
                    .help("Estimated locally from Claude Code logs — matches Claude's 5-hour billing windows.")
            }
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
            if let update = model.availableUpdate {
                Link(destination: update.url) {
                    Label("Update available — v\(update.version)", systemImage: "arrow.down.circle")
                        .font(.callout)
                }
                .foregroundStyle(Theme.accent)
                .help("Opens the GitHub release page")
            }
            HStack(spacing: 8) {
                Button { openDashboard() } label: {
                    Label("Dashboard", systemImage: "chart.bar.xaxis")
                }
                .keyboardShortcut("d", modifiers: .command)
                Spacer()
                TimelineView(.periodic(from: .now, by: 60)) { context in
                    // When logged in, "Updated" reflects the ACCOUNT fetch time (the
                    // % is what the user cares about), not the local log scan (which
                    // never fails and would always read "just now").
                    let stamp = model.snapshot.account?.fetchedAt ?? model.snapshot.lastUpdated
                    Text("Updated \(Formatting.relativeUpdated(stamp, now: context.date))")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                Button("Quit") { NSApp.terminate(nil) }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .keyboardShortcut("q", modifiers: .command)
            }
            .font(.callout)
        }
    }

    // MARK: - Helpers

    private func iconButton(_ name: String, help: String, _ action: @escaping () -> Void) -> some View {
        HoverIconButton(name: name, help: help, action: action)
    }

    private func metric(title: String, value: String, help: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value).font(.title3.weight(.semibold)).monospacedDigit()
            if let help {
                HStack(spacing: 3) {
                    Text(title).font(.caption2).foregroundStyle(.secondary)
                    Image(systemName: "info.circle")
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                }
                .help(help)
            } else {
                Text(title).font(.caption2).foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(value)
    }

    private func openDashboard() {
        openWindow(id: AppWindowID.dashboard)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func openLogin() {
        openWindow(id: AppWindowID.accountLogin)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// In a menu-bar-only (accessory) app the settings window won't take focus
    /// unless the app is activated first. The legacy `showSettingsWindow:`
    /// selector no longer resolves on current macOS — `openSettings` is the
    /// supported action.
    private func openSettingsWindow() {
        NSApp.activate(ignoringOtherApps: true)
        openSettings()
        dismiss()
    }
}

/// Borderless icon button with a hover highlight (borderless buttons on macOS
/// give no hover feedback of their own) and a proper VoiceOver name.
private struct HoverIconButton: View {
    let name: String
    let help: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: name)
                .font(.system(size: 13, weight: .medium))
                .frame(width: 26, height: 26)
                .background(Circle().fill(Color.primary.opacity(hovering ? 0.08 : 0)))
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .foregroundStyle(.secondary)
        .onHover { hovering = $0 }
        .help(help)
        .accessibilityLabel(help)
    }
}
