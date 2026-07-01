import Foundation
import UsageMeterKit

/// Synthetic, attractive, PII-free data for marketing screenshots and for
/// previewing the app before there's any real Claude Code history.
/// Enabled by the `USAGEMETER_DEMO=1` environment variable (see `make demo`) or
/// the "Show sample data" Settings toggle.
enum DemoData {
    /// UserDefaults key backing the runtime "Show sample data" toggle. Kept next
    /// to `isEnabled` so the gate and the persisted setting can't drift apart.
    static let defaultsKey = "settings.showSampleData"

    /// Sample mode is active when the screenshot env var is set OR the user turned
    /// on "Show sample data" in Settings — read live so the toggle takes effect at
    /// runtime (every demo call site goes through this single gate).
    static var isEnabled: Bool {
        ProcessInfo.processInfo.environment["USAGEMETER_DEMO"] == "1"
            || UserDefaults.standard.bool(forKey: defaultsKey)
    }

    static func snapshot(now: Date = Date()) -> EngineSnapshot {
        EngineSnapshot(
            claudeCode: claudeCode(now: now),
            status: ServiceStatus(indicator: .none, description: "All Systems Operational", fetchedAt: now),
            account: account(now: now),
            lastUpdated: now)
    }

    /// Synthetic account — omitted in the local-only App Store build so demo
    /// screenshots match that build (Claude Code + status only, no account %).
    private static func account(now: Date) -> AccountUsage? {
        #if APPSTORE
        return nil
        #else
        return AccountUsage(
            session: UsageMetric(percent: 42, resetsAt: now.addingTimeInterval(2 * 3600 + 9 * 60)),
            weekly: UsageMetric(percent: 18, resetsAt: now.addingTimeInterval(3 * 86_400 + 4 * 3600)),
            weeklyOpus: UsageMetric(percent: 31, resetsAt: now.addingTimeInterval(3 * 86_400 + 4 * 3600)),
            spend: SpendInfo(usedMinor: 0, currency: "USD", exponent: 2, canPurchaseCredits: true),
            fetchedAt: now)
        #endif
    }

    private static func claudeCode(now: Date) -> ClaudeCodeStats {
        let calc = CostCalculator(pricing: .defaults)
        let calendar = Calendar.current
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"

        var byDay: [DailyUsage] = []
        var total = TokenUsage.zero
        var today = TokenUsage.zero

        for i in 0..<150 {
            guard let date = calendar.date(byAdding: .day, value: -i, to: calendar.startOfDay(for: now)) else { continue }
            let weekday = calendar.component(.weekday, from: date)
            let weekend = (weekday == 1 || weekday == 7)
            // Deterministic wave + occasional spikes → realistic-looking history.
            var factor = max(0.05, 0.5 + 0.4 * sin(Double(i) / 4.0) + 0.12 * cos(Double(i) / 13.0))
            factor *= weekend ? 0.4 : 1.0
            if i % 23 == 3 { factor *= 2.6 }
            if i > 128 { factor *= 0.25 }
            let usage = TokenUsage(
                inputTokens: Int(140_000 * factor),
                cacheCreationTokens: Int(900_000 * factor),
                cacheReadTokens: Int(26_000_000 * factor),
                outputTokens: Int(1_900_000 * factor))
            byDay.append(DailyUsage(day: formatter.string(from: date), usage: usage,
                                    estimatedCost: calc.cost(usage: usage, family: .opus)))
            total += usage
            if i == 0 { today = usage }
        }
        byDay.reverse()

        func model(_ family: ModelFamily, _ u: TokenUsage) -> ModelUsage {
            ModelUsage(family: family, usage: u, estimatedCost: calc.cost(usage: u, family: family))
        }
        let byModel = [
            model(.opus, TokenUsage(inputTokens: 5_200_000, cacheCreationTokens: 42_000_000,
                                    cacheReadTokens: 1_850_000_000, outputTokens: 24_000_000)),
            model(.fable, TokenUsage(inputTokens: 1_100_000, cacheCreationTokens: 8_000_000,
                                     cacheReadTokens: 330_000_000, outputTokens: 5_400_000)),
            model(.sonnet, TokenUsage(inputTokens: 600_000, cacheCreationTokens: 3_200_000,
                                      cacheReadTokens: 120_000_000, outputTokens: 2_100_000)),
            model(.haiku, TokenUsage(inputTokens: 220_000, cacheCreationTokens: 700_000,
                                     cacheReadTokens: 26_000_000, outputTokens: 540_000))
        ]

        func project(_ name: String, _ u: TokenUsage, _ sessions: Int) -> ProjectUsage {
            ProjectUsage(projectID: name, displayName: name, usage: u,
                         estimatedCost: calc.cost(usage: u, family: .opus), sessionCount: sessions)
        }
        let byProject = [
            project("usage-meter", TokenUsage(cacheReadTokens: 980_000_000, outputTokens: 12_000_000), 64),
            project("web-platform", TokenUsage(cacheReadTokens: 520_000_000, outputTokens: 6_400_000), 38),
            project("data-pipeline", TokenUsage(cacheReadTokens: 240_000_000, outputTokens: 3_100_000), 21),
            project("ios-client", TokenUsage(cacheReadTokens: 110_000_000, outputTokens: 1_500_000), 14),
            project("infra-scripts", TokenUsage(cacheReadTokens: 60_000_000, outputTokens: 820_000), 9)
        ]

        return ClaudeCodeStats(
            total: total,
            totalEstimatedCost: calc.cost(usage: total, family: .opus),
            today: today,
            todayEstimatedCost: calc.cost(usage: today, family: .opus),
            byModel: byModel,
            byProject: byProject,
            byDay: byDay,
            sessionCount: 146,
            recordCount: 9_842,
            activeBlock: UsageBlock(start: now.addingTimeInterval(-1 * 3600),
                                    end: now.addingTimeInterval(4 * 3600),
                                    usage: today, estimatedCost: calc.cost(usage: today, family: .opus),
                                    isActive: true))
    }
}
