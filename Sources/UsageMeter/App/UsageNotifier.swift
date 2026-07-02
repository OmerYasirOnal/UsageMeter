import Foundation
import UserNotifications
import UsageMeterKit

/// Raises local notifications at 50/75/90% and when burn-rate projects hitting a
/// limit before reset. Decision logic lives in `NotificationPolicy` (Kit); this is
/// the plumbing + per-metric state persistence.
@MainActor
final class UsageNotifier {
    private let defaultsKey = "notifier.metricStates.v1"
    private var states: [String: MetricAlertState] = [:]
    private(set) var authorized = false

    init() { load() }

    /// Needs a real app bundle (not an unbundled `swift run`).
    private var isAvailable: Bool { Bundle.main.bundleIdentifier != nil }

    func requestAuthorizationIfNeeded() {
        guard isAvailable else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, _ in
            Task { @MainActor in self.authorized = granted }
        }
    }

    /// Evaluate the latest snapshot data and fire any due notifications.
    /// Account metrics need Source A; the daily-budget alert works from local
    /// Source-B data alone (incl. the local-only App Store build).
    /// Only advances de-dup state when delivery is actually possible (bundled +
    /// authorized), so thresholds aren't silently "used up" before we can notify.
    func evaluate(_ account: AccountUsage?, todayCost: Double?, dailyBudgetUSD: Double,
                  enabled: Bool, now: Date = Date()) {
        guard enabled, isAvailable, authorized else { return }
        var toFire: [UsageAlert] = []
        if let account {
            let metrics: [(String, UsageMetric?)] = [
                ("Session", account.session),
                ("Weekly", account.weekly),
                ("Weekly Opus", account.weeklyOpus)
            ]
            for (name, metric) in metrics {
                guard let metric else { continue }
                let result = NotificationPolicy.evaluate(
                    metricName: name, percent: metric.percent, resetsAt: metric.resetsAt,
                    now: now, prior: states[name])
                states[name] = result.state
                toFire.append(contentsOf: result.alerts)
            }
        }
        let budgetResult = DailyBudgetPolicy.evaluate(
            todayCost: todayCost, budgetUSD: dailyBudgetUSD,
            dayKey: Self.dayKey(for: now), prior: states[DailyBudgetPolicy.metricName])
        states[DailyBudgetPolicy.metricName] = budgetResult.state
        toFire.append(contentsOf: budgetResult.alerts)
        save()
        toFire.forEach(post)
    }

    /// Local-calendar day key (what a user means by "today").
    private static func dayKey(for date: Date) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return "\(c.year ?? 0)-\(c.month ?? 0)-\(c.day ?? 0)"
    }

    /// Clear remembered state (e.g. on logout) so a fresh login re-alerts cleanly.
    func reset() {
        states = [:]
        save()
    }

    // MARK: - Private

    private func post(_ alert: UsageAlert) {
        guard isAvailable else { return }
        let content = UNMutableNotificationContent()
        content.title = alert.title
        content.body = alert.body
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: "\(alert.id)-\(UUID().uuidString)", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let decoded = try? JSONDecoder().decode([String: MetricAlertState].self, from: data) else { return }
        states = decoded
    }

    private func save() {
        if let data = try? JSONEncoder().encode(states) {
            UserDefaults.standard.set(data, forKey: defaultsKey)
        }
    }
}
