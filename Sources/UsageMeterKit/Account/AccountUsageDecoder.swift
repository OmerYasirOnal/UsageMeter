import Foundation

/// Decodes the claude.ai usage JSON into `AccountUsage`.
///
/// ⚠️ HEURISTIC FIRST CUT. The real endpoint + exact field names are discovered
/// empirically by the in-app capture (the brief forbids guessing the endpoint).
/// Until a real response is captured and this is replaced by an exact `Codable`
/// decoder, we walk the JSON and classify each "metric-shaped" object (a
/// utilization/percent number, optionally with a reset time) by its *nearest*
/// key:
///   • key contains "opus"                         → weekly Opus limit
///   • key contains "week"/"seven"/"7day"/"7_day"  → weekly limit
///   • key contains "session"/"five"/"hour"/"5h"   → current session
///
/// Robustness guards: deterministic key priority (no Dictionary-order
/// nondeterminism), a 0...100 plausibility range so raw counts aren't read as
/// percentages, relative-duration reset handling, reset-date sanity bounds, and a
/// recursion-depth cap. Swappable — replace `decode(_:)` once the shape is known.
public enum AccountUsageDecoder {
    private static let maxDepth = 24
    /// Percent keys in priority order (most specific first). Deliberately excludes
    /// fuzzy keys like "usage"/"used"/"ratio" that often name raw counts.
    private static let percentTokens = [
        "utilization", "percentage", "percent", "pct", "used_percent", "usage_percent", "fraction"
    ]
    private static let durationTokens = ["reset_in", "resets_in", "expires_in", "seconds_until", "until_reset"]
    private static let absoluteResetTokens = ["reset", "refresh", "expires", "renew", "next"]

    public static func decode(_ data: Data, now: Date = Date()) -> AccountUsage? {
        // decodeExact returns nil unless it found a metric or spend, so this also
        // falls through to the heuristic for unknown shapes.
        if let exact = decodeExact(data, now: now) { return exact }
        return decodeHeuristic(data, now: now)
    }

    // MARK: - Exact decoder for the real claude.ai /usage response

    private struct RawUsage: Decodable {
        struct Window: Decodable { let utilization: Double?; let resets_at: String? }
        struct Limit: Decodable {
            struct Scope: Decodable {
                struct Model: Decodable { let id: String?; let display_name: String? }
                let model: Model?
            }
            let kind: String?; let group: String?; let percent: Double?
            let resets_at: String?; let is_active: Bool?
            let scope: Scope?
        }
        struct SpendUsed: Decodable { let amount_minor: Int?; let currency: String?; let exponent: Int? }
        struct Spend: Decodable { let used: SpendUsed?; let can_purchase_credits: Bool? }
        let five_hour: Window?
        let seven_day: Window?
        let seven_day_opus: Window?
        let limits: [Limit]?
        let spend: Spend?
    }

    static func decodeExact(_ data: Data, now: Date) -> AccountUsage? {
        guard data.count <= 1_000_000,
              let raw = try? JSONDecoder().decode(RawUsage.self, from: data) else { return nil }

        func reset(_ s: String?) -> Date? {
            s.flatMap { parseDate($0) }.flatMap { isSane($0, now: now) ? $0 : nil }
        }

        // PRIMARY: the per-window fields map 1:1 to the headline limits and carry the
        // utilization ALREADY AS A 0...100 PERCENT (verified against the real
        // response: five_hour=39, seven_day=8 ⇒ "Current session 39%", "All models
        // 8%"). Do NOT rescale.
        func windowMetric(_ window: RawUsage.Window?) -> UsageMetric? {
            guard let window, let u = window.utilization, u >= 0 else { return nil }
            return UsageMetric(percent: min(100.0, max(0.0, u)), resetsAt: reset(window.resets_at))
        }
        var session = windowMetric(raw.five_hour)
        var weekly = windowMetric(raw.seven_day)
        var weeklyOpus = windowMetric(raw.seven_day_opus)
        var weeklyFable: UsageMetric?

        // FALLBACK: the `limits` array (also 0...100) for any category the windows
        // didn't provide. Model-scoped limits (`scope.model.display_name`, e.g.
        // Fable) are classified FIRST so they don't fall through to the generic
        // kind/group text heuristics below and get silently absorbed into the
        // plain weekly bucket.
        for limit in raw.limits ?? [] {
            guard let p = limit.percent else { continue }
            let metric = UsageMetric(percent: min(100.0, max(0.0, p)), resetsAt: reset(limit.resets_at))
            let modelName = (limit.scope?.model?.display_name ?? limit.scope?.model?.id ?? "").lowercased()
            if modelName.contains("fable") {
                weeklyFable = weeklyFable ?? metric
                continue
            }
            let key = ((limit.kind ?? "") + " " + (limit.group ?? "")).lowercased()
            if key.contains("opus") {
                weeklyOpus = weeklyOpus ?? metric
            } else if key.contains("sonnet") || key.contains("haiku") {
                continue
            } else if key.contains("five") || key.contains("hour") || key.contains("session") {
                session = session ?? metric
            } else if key.contains("seven") || key.contains("week") {
                weekly = weekly ?? metric
            }
        }

        var spend: SpendInfo?
        if let used = raw.spend?.used, let minor = used.amount_minor {
            spend = SpendInfo(usedMinor: minor,
                              currency: used.currency ?? "USD",
                              exponent: used.exponent ?? 2,
                              canPurchaseCredits: raw.spend?.can_purchase_credits ?? false)
        }

        let usage = AccountUsage(session: session, weekly: weekly, weeklyOpus: weeklyOpus,
                                 weeklyFable: weeklyFable, spend: spend, fetchedAt: now)
        return (usage.hasAnyMetric || usage.spend != nil) ? usage : nil
    }

    // MARK: - Heuristic fallback (unknown shapes)

    static func decodeHeuristic(_ data: Data, now: Date) -> AccountUsage? {
        guard data.count <= 1_000_000,
              let root = try? JSONSerialization.jsonObject(with: data) else { return nil }

        var session: UsageMetric?
        var weekly: UsageMetric?
        var weeklyOpus: UsageMetric?
        var weeklyFable: UsageMetric?

        walk(root, nearestKey: "", depth: 0) { dict, nearestKey in
            guard let metric = metric(from: dict, now: now) else { return }
            let key = nearestKey.lowercased()
            if key.contains("opus") {
                weeklyOpus = weeklyOpus ?? metric
            } else if key.contains("fable") {
                weeklyFable = weeklyFable ?? metric
            } else if key.contains("week") || key.contains("seven")
                        || key.contains("7day") || key.contains("7_day") {
                weekly = weekly ?? metric
            } else if key.contains("session") || key.contains("five")
                        || key.contains("hour") || key.contains("5h") || key.contains("5_hour") {
                session = session ?? metric
            }
        }

        guard session != nil || weekly != nil || weeklyOpus != nil || weeklyFable != nil else { return nil }
        return AccountUsage(session: session, weekly: weekly, weeklyOpus: weeklyOpus,
                            weeklyFable: weeklyFable, fetchedAt: now)
    }

    // MARK: - Heuristics

    static func metric(from dict: [String: Any], now: Date) -> UsageMetric? {
        guard let percent = percent(in: dict) else { return nil }
        return UsageMetric(percent: percent, resetsAt: resetDate(in: dict, now: now))
    }

    /// Deterministic: try each percent token in priority order, scanning the dict's
    /// keys in sorted order. Accept only plausible 0...100 results.
    static func percent(in dict: [String: Any]) -> Double? {
        let keys = dict.keys.sorted()
        for token in percentTokens {
            for key in keys where key.lowercased().contains(token) {
                guard let number = (dict[key] as? NSNumber)?.doubleValue else { continue }
                let scaled = number <= 1.0 ? number * 100.0 : number
                if (0.0...100.5).contains(scaled) { return min(100.0, scaled) }
            }
        }
        return nil
    }

    static func resetDate(in dict: [String: Any], now: Date) -> Date? {
        let keys = dict.keys.sorted()
        // Relative durations first ("resets in N seconds").
        for token in durationTokens {
            for key in keys where key.lowercased().contains(token) {
                if let n = (dict[key] as? NSNumber)?.doubleValue, n >= 0, n < 60 * 86_400 {
                    return now.addingTimeInterval(n)
                }
            }
        }
        // Absolute timestamps (ISO or epoch s/ms), sanity-bounded.
        for token in absoluteResetTokens {
            for key in keys where key.lowercased().contains(token) {
                if let s = dict[key] as? String, let date = parseDate(s), isSane(date, now: now) {
                    return date
                }
                if let n = (dict[key] as? NSNumber)?.doubleValue {
                    let date = n > 1_000_000_000_000
                        ? Date(timeIntervalSince1970: n / 1000)
                        : Date(timeIntervalSince1970: n)
                    if isSane(date, now: now) { return date }
                }
            }
        }
        return nil
    }

    private static func isSane(_ date: Date, now: Date) -> Bool {
        date > now.addingTimeInterval(-86_400) && date < now.addingTimeInterval(60 * 86_400)
    }

    static func parseDate(_ s: String) -> Date? {
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = withFraction.date(from: s) { return d }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: s)
    }

    /// Depth-first walk; invokes `visit` for every dictionary with its NEAREST key
    /// (the immediate key that names it), avoiding ancestor-token bleed-through.
    private static func walk(_ node: Any, nearestKey: String, depth: Int,
                             visit: ([String: Any], String) -> Void) {
        guard depth < maxDepth else { return }
        if let dict = node as? [String: Any] {
            visit(dict, nearestKey)
            for (key, value) in dict {
                walk(value, nearestKey: key, depth: depth + 1, visit: visit)
            }
        } else if let array = node as? [Any] {
            for value in array {
                walk(value, nearestKey: nearestKey, depth: depth + 1, visit: visit)
            }
        }
    }
}
