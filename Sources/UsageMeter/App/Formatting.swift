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

    /// USD cost, or "n/a" when unpriced.
    static func cost(_ value: Double?) -> String {
        guard let value else { return "n/a" }
        if value > 0 && value < 0.01 {
            return "<$0.01"
        }
        return String(format: "$%.2f", value)
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

    /// "Mon, 07:59".
    static func weekdayTime(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = .current
        f.dateFormat = "EEE, HH:mm"
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
