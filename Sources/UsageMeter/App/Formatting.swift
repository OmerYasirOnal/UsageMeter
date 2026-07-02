import SwiftUI
import UsageMeterKit

/// Presentation helpers (pure functions, no state).
enum Formatting {
    /// Compact token count: 1.2M, 34.5K, 920.
    static func tokens(_ count: Int) -> String {
        let n = Double(count)
        switch count {
        case 1_000_000...:
            return String(format: "%.1fM", n / 1_000_000)
        case 1_000...:
            return String(format: "%.1fK", n / 1_000)
        default:
            return "\(count)"
        }
    }

    /// The Claude Code "API value" estimate (always USD — API rates are USD),
    /// or "n/a" when unpriced. Formatted with en_US separators on purpose: a
    /// USD estimate rendered as "$5.921,79" on comma-decimal locales misreads
    /// as $5.92. Real account-currency spend (`money`) stays locale-aware.
    static func cost(_ value: Double?) -> String {
        guard let value else { return "n/a" }
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        f.locale = Locale(identifier: "en_US")
        if value > 0 && value < 0.01 { return "<$0.01" }
        return f.string(from: value as NSNumber) ?? String(format: "$%.2f", value)
    }

    /// Ultra-compact cost for the menu bar ("$112", "$1.3K") — fixed shape so
    /// the status item width stays stable between refreshes.
    static func menuBarCost(_ value: Double) -> String {
        if value >= 1000 { return String(format: "$%.1fK", value / 1000) }
        return "$\(Int(value.rounded()))"
    }

    /// Chart-axis token count without decimal noise: "400M", "1.5M", "34K".
    static func axisTokens(_ count: Int) -> String {
        func trim(_ v: Double, _ suffix: String) -> String {
            v == v.rounded()
                ? String(format: "%.0f%@", v, suffix)
                : String(format: "%.1f%@", v, suffix)
        }
        let n = Double(count)
        switch count {
        case 1_000_000...: return trim(n / 1_000_000, "M")
        case 1_000...: return trim(n / 1_000, "K")
        default: return "\(count)"
        }
    }

    /// Real money in the account's currency (e.g. "$0.00", "€3.20").
    static func money(_ amount: Double, currency: String) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = currency
        f.locale = .current
        return f.string(from: amount as NSNumber) ?? String(format: "%.2f %@", amount, currency)
    }

    /// "just now", "3m ago", "2h ago", or "never".
    static func relativeUpdated(_ date: Date?, now: Date = Date()) -> String {
        guard let date else { return "never" }
        let seconds = max(0, now.timeIntervalSince(date))
        switch seconds {
        case ..<45:
            return "just now"
        case ..<3600:
            return "\(Int((seconds / 60).rounded(.down)))m ago"
        case ..<86_400:
            return "\(Int((seconds / 3600).rounded(.down)))h ago"
        default:
            return "\(Int((seconds / 86_400).rounded(.down)))d ago"
        }
    }

    /// A duration like "2h 10m", "45m", or "<1m" for a seconds interval.
    static func duration(_ seconds: TimeInterval) -> String {
        let s = max(0, Int(seconds))
        let h = s / 3600, m = (s % 3600) / 60
        if h > 0 { return "\(h)h \(m)m" }
        if m > 0 { return "\(m)m" }
        return "<1m"
    }

    /// Countdown like "2h 14m" until the given date, or nil if past/unknown.
    static func countdown(to date: Date?, now: Date = Date()) -> String? {
        guard let date else { return nil }
        let seconds = date.timeIntervalSince(now)
        guard seconds > 0 else { return nil }
        let hours = Int(seconds) / 3600
        let minutes = (Int(seconds) % 3600) / 60
        if hours > 0 { return "\(hours)h \(minutes)m" }
        return "\(minutes)m"
    }

    /// "16:29" local clock time.
    static func clockTime(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = .current
        f.setLocalizedDateFormatFromTemplate("Hm")
        return f.string(from: date)
    }

    /// "Mon, 07:59" (or "Mon, 7:59 AM" — respects the 12/24-hour preference).
    static func weekdayTime(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = .current
        f.setLocalizedDateFormatFromTemplate("EEEjmm")
        return f.string(from: date)
    }

    /// Reset description matching the reference app:
    ///  - within a day → "in 2h 15m (16:29)"
    ///  - further out  → "Mon, 07:59"
    static func resetDescription(to date: Date?, now: Date = Date()) -> String? {
        guard let date else { return nil }
        let seconds = date.timeIntervalSince(now)
        if seconds <= 0 { return "now" }
        if seconds < 86_400 {
            let cd = countdown(to: date, now: now) ?? ""
            return "in \(cd) (\(clockTime(date)))"
        }
        return weekdayTime(date)
    }
}
