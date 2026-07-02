import SwiftUI
import AppKit
import Charts
import UniformTypeIdentifiers
import UsageMeterKit

/// The full dashboard: free, private, and visually consistent with the popover.
struct DashboardView: View {
    @EnvironmentObject private var model: AppModel
    @State private var range: DashboardRange = .days30
    // Skip the fade-in for demo/screenshot rendering (ImageRenderer doesn't run .task).
    @State private var appeared = DemoData.isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var allPoints: [DailyPoint] {
        DashboardMetrics.dailyPoints(from: model.snapshot.claudeCode)
    }

    var body: some View {
        // Computed once per render and threaded into the subviews.
        let all = allPoints
        let points = DashboardMetrics.filtered(all, range: range)
        let insights = DashboardMetrics.insights(points)

        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                title
                if DemoData.isEnabled { SampleDataBanner() }
                if let account = model.snapshot.account, account.hasAnyMetric {
                    accountCards(account)
                }
                historyCard(points)
                insightsRow(insights)
                activityCard(all)
                claudeCodeSummary
                if !model.snapshot.claudeCode.byModel.isEmpty { byModelCard }
                if !model.snapshot.claudeCode.byProject.isEmpty { byProjectCard }
                footer
            }
            .padding(24)
            .frame(maxWidth: 920, alignment: .leading)
            .frame(maxWidth: .infinity)
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 8)
        }
        .frame(minWidth: 900, minHeight: 640)
        .tint(Theme.accent)
        .preferredColorScheme(model.settings.appearance.colorScheme)
        .managesActivationPolicy()
        .task {
            // Reveal immediately with cached data — don't stay blank while a slow
            // refresh (log scan / network) runs.
            if reduceMotion {
                appeared = true
            } else {
                withAnimation(.easeOut(duration: 0.45)) { appeared = true }
            }
            await model.refresh()
        }
    }

    // MARK: - Title + export

    private var title: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Dashboard").font(.largeTitle.bold())
                Text("Your Claude usage at a glance — free & private. Only token counts, models, and timestamps are read.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
            Menu {
                Button { exportCSV() } label: { Label("Export CSV (current range)", systemImage: "tablecells") }
                Button { exportImage() } label: { Label("Export image (PNG)", systemImage: "photo") }
            } label: {
                Label("Export", systemImage: "square.and.arrow.up")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
    }

    // MARK: - Account cards

    private func accountCards(_ account: AccountUsage) -> some View {
        HStack(spacing: 14) {
            if let s = account.session { accountCard("Current Session", key: "Session", s) }
            if let w = account.weekly { accountCard("Weekly Limit", key: "Weekly", w) }
            if let o = account.weeklyOpus { accountCard("Weekly Opus", key: "Weekly Opus", o) }
            if let spend = account.spend { spendCard(spend) }
        }
    }

    private func accountCard(_ title: String, key: String, _ metric: UsageMetric) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
            Text("\(metric.displayPercent)%")
                .font(.system(size: 32, weight: .bold, design: .rounded)).monospacedDigit()
                .foregroundStyle(Theme.numeralColor(metric.percent))
            UsageBar(percent: metric.percent, color: Theme.usageColor(metric.percent))
            TimelineView(.periodic(from: .now, by: 60)) { context in
                VStack(alignment: .leading, spacing: 5) {
                    if let reset = Formatting.resetDescription(to: metric.resetsAt, now: context.date) {
                        Text("Resets \(reset)").font(.caption).foregroundStyle(.secondary)
                    }
                    dashProjection(model.projection(for: key, metric, now: context.date))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    /// "When will you run out" — the burn projection on a dashboard account card.
    @ViewBuilder
    private func dashProjection(_ proj: UsageProjection) -> some View {
        let rate = proj.ratePerHour.map { "≈ \(String(format: "%.0f", $0))%/hr" }
        switch proj.status {
        case .exhausts(let ttl, _):
            projStack("exclamationmark.triangle.fill", Theme.warning,
                      "Hits the limit in ~\(Formatting.duration(ttl)) — before it resets", rate)
        case .resetsFirst(let ttl):
            projStack("checkmark.circle", Theme.ok,
                      "Resets before the limit (~\(Formatting.duration(ttl)) to limit)", rate)
        case .gathering:
            Text("Gathering your pace…").font(.caption2).foregroundStyle(.tertiary)
        case .notRising:
            Text("Not rising right now").font(.caption2).foregroundStyle(.tertiary)
        }
    }

    private func projStack(_ icon: String, _ tint: Color, _ text: String, _ rate: String?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Label(text, systemImage: icon).foregroundStyle(tint)
                .fixedSize(horizontal: false, vertical: true)
            if let rate { Text(rate).foregroundStyle(.secondary) }
        }
        .font(.caption2)
    }

    private func spendCard(_ spend: SpendInfo) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Pay-as-you-go").font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
            Text(Formatting.money(spend.usedAmount, currency: spend.currency))
                .font(.system(size: 32, weight: .bold, design: .rounded)).monospacedDigit()
                .foregroundStyle(.primary)
            Text("real spend (this period)").font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    // MARK: - Usage history chart

    private func historyCard(_ points: [DailyPoint]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Usage History").font(.title3.bold())
                    Text("Claude Code tokens per day").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Picker("", selection: $range) {
                    ForEach(DashboardRange.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                .fixedSize()
            }
            if points.allSatisfy({ $0.tokens == 0 }) {
                Text("No Claude Code usage in this range yet.")
                    .font(.callout).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 200)
            } else {
                Chart(points) { point in
                    BarMark(
                        x: .value("Day", point.date, unit: .day),
                        y: .value("Tokens", point.tokens)
                    )
                    .foregroundStyle(Theme.chartGradient)
                    .cornerRadius(3)
                }
                .chartYAxis {
                    AxisMarks { value in
                        AxisGridLine()
                        AxisValueLabel {
                            if let i = value.as(Int.self) { Text(Formatting.axisTokens(i)).font(.caption2) }
                        }
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .stride(by: .day, count: xStrideCount(points))) { _ in
                        AxisGridLine()
                        AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                    }
                }
                .frame(height: 220)
                .animation(.easeOut(duration: 0.4), value: range)
            }
        }
        .card()
    }

    private func xStrideCount(_ points: [DailyPoint]) -> Int {
        switch range {
        case .days7: return 1
        case .days30: return 5
        case .days90: return 14
        case .all:
            guard let first = points.first?.date, let last = points.last?.date else { return 7 }
            let span = Calendar.current.dateComponents([.day], from: first, to: last).day ?? points.count
            return max(1, span / 8)
        }
    }

    // MARK: - Insights

    private func insightsRow(_ insights: UsageInsights) -> some View {
        // Icons stay neutral: the semantic color ramp is reserved for limit
        // proximity — a red flame on a neutral fact reads as a false alarm.
        HStack(spacing: 14) {
            insightCard("chart.bar.fill", Formatting.tokens(insights.averageDailyTokens), "Avg / active day", .secondary)
            insightCard("flame.fill", insights.peak.map { Formatting.tokens($0.tokens) } ?? "—", peakLabel(insights), .secondary)
            insightCard("calendar", "\(insights.activeDays)", "Active days", .secondary)
            if model.settings.showApiValue {
                insightCard("dollarsign.circle.fill", Formatting.cost(insights.totalCost), "API value (range)", .secondary)
            } else {
                insightCard("number", Formatting.tokens(insights.totalTokens), "Total tokens (range)", .secondary)
            }
        }
    }

    private func peakLabel(_ insights: UsageInsights) -> String {
        guard let peak = insights.peak else { return "Peak day" }
        return "Peak · \(peak.date.formatted(.dateTime.month(.abbreviated).day()))"
    }

    private func insightCard(_ icon: String, _ value: String, _ label: String, _ tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: icon).foregroundStyle(tint)
            Text(value).font(.title2.weight(.bold)).monospacedDigit()
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    // MARK: - Activity grid

    private func activityCard(_ allPoints: [DailyPoint]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 1) {
                Text("Activity").font(.title3.bold())
                Text("Daily usage over the last 12 months").font(.caption).foregroundStyle(.secondary)
            }
            ActivityGrid(points: allPoints)
        }
        .card()
    }

    // MARK: - Claude Code summary

    private var claudeCodeSummary: some View {
        let cc = model.snapshot.claudeCode
        return VStack(alignment: .leading, spacing: 12) {
            Text("Claude Code").font(.title3.bold())
            HStack(spacing: 28) {
                stat("Responses", "\(cc.recordCount)")
                stat("Sessions", "\(cc.sessionCount)")
                stat("All-time tokens", Formatting.tokens(cc.total.totalTokens))
                if model.settings.showApiValue {
                    stat("All-time API value", Formatting.cost(cc.totalEstimatedCost))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.title3.weight(.bold)).monospacedDigit()
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
    }

    // MARK: - By model

    private var byModelCard: some View {
        let models = model.snapshot.claudeCode.byModel
        let maxTokens = max(1, models.map { $0.usage.totalTokens }.max() ?? 1)
        return VStack(alignment: .leading, spacing: 12) {
            Text("By model").font(.title3.bold())
            ForEach(models) { m in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(m.family.displayName).font(.callout.weight(.medium))
                        Spacer()
                        Text(Formatting.tokens(m.usage.totalTokens)).monospacedDigit()
                        Text(Formatting.cost(m.estimatedCost)).foregroundStyle(.secondary)
                            .frame(width: 84, alignment: .trailing).monospacedDigit()
                    }
                    .font(.callout)
                    UsageBar(percent: Double(m.usage.totalTokens) / Double(maxTokens) * 100,
                             color: Theme.data, height: 6)
                }
            }
        }
        .card()
    }

    // MARK: - By project

    private var byProjectCard: some View {
        let projects = Array(model.snapshot.claudeCode.byProject.prefix(8))
        return VStack(alignment: .leading, spacing: 10) {
            Text("By project").font(.title3.bold())
            HStack {
                Text("Project").frame(maxWidth: .infinity, alignment: .leading)
                Text("Sessions").frame(width: 70, alignment: .trailing)
                Text("Tokens").frame(width: 80, alignment: .trailing)
                Text("Cost").frame(width: 80, alignment: .trailing)
            }
            .font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
            ForEach(projects) { p in
                HStack {
                    Text(p.displayName).lineLimit(1).truncationMode(.middle)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text("\(p.sessionCount)").frame(width: 70, alignment: .trailing)
                    Text(Formatting.tokens(p.usage.totalTokens)).frame(width: 80, alignment: .trailing)
                    Text(Formatting.cost(p.estimatedCost)).foregroundStyle(.secondary)
                        .frame(width: 80, alignment: .trailing)
                }
                .font(.callout).monospacedDigit()
            }
        }
        .card()
    }

    // MARK: - Footer

    private var footer: some View {
        Text("Privacy: UsageMeter reads only token counts, model names, and timestamps — never your messages. Everything stays on this Mac.")
            .font(.caption2).foregroundStyle(.tertiary)
            .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - Export

    /// A compact, brandable card rendered to PNG for sharing.
    private var shareableCard: some View {
        let cc = model.snapshot.claudeCode
        return VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                Image(systemName: "gauge.with.dots.needle.50percent").foregroundStyle(Theme.data)
                Text("UsageMeter").font(.title2.bold())
            }
            if let a = model.snapshot.account, a.hasAnyMetric {
                HStack(spacing: 28) {
                    if let s = a.session { shareStat("Session", "\(s.displayPercent)%") }
                    if let w = a.weekly { shareStat("Weekly", "\(w.displayPercent)%") }
                    if let o = a.weeklyOpus { shareStat("Weekly Opus", "\(o.displayPercent)%") }
                }
            }
            HStack(spacing: 28) {
                shareStat("All-time tokens", Formatting.tokens(cc.total.totalTokens))
                if model.settings.showApiValue { shareStat("API value", Formatting.cost(cc.totalEstimatedCost)) }
                shareStat("Sessions", "\(cc.sessionCount)")
            }
            Text("Tracked locally & privately with UsageMeter")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(28)
        .frame(width: 460, alignment: .leading)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func shareStat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.title2.weight(.bold)).monospacedDigit().foregroundStyle(Theme.data)
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
    }

    private func exportCSV() {
        let daysInRange = Set(DashboardMetrics.filtered(allPoints, range: range).map { $0.day })
        var csv = "date,tokens,input,cache_creation,cache_read,output,api_value_usd\n"
        for d in model.snapshot.claudeCode.byDay where daysInRange.contains(d.day) {
            let u = d.usage
            let cost = d.estimatedCost.map { String(format: "%.4f", $0) } ?? ""
            csv += "\(d.day),\(u.totalTokens),\(u.inputTokens),\(u.cacheCreationTokens),\(u.cacheReadTokens),\(u.outputTokens),\(cost)\n"
        }
        save(data: Data(csv.utf8), suggestedName: "usagemeter-\(range.label).csv", type: .commaSeparatedText)
    }

    private func exportImage() {
        let renderer = ImageRenderer(content: shareableCard)
        renderer.scale = 2
        guard let image = renderer.nsImage,
              let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else {
            present(error: "Couldn't render the image.")
            return
        }
        save(data: png, suggestedName: "usagemeter-summary.png", type: .png)
    }

    private func save(data: Data, suggestedName: String, type: UTType) {
        NSApp.activate(ignoringOtherApps: true)
        let panel = NSSavePanel()
        panel.nameFieldStringValue = suggestedName
        panel.allowedContentTypes = [type]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try data.write(to: url)
        } catch {
            present(error: error.localizedDescription)
        }
    }

    private func present(error message: String) {
        let alert = NSAlert()
        alert.messageText = "Export failed"
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.runModal()
    }
}
