import Foundation

/// How this user's tokens typically accumulate over a local day, learned from
/// the last complete days of history. Powers the day-end forecast ("on pace for
/// ~X today") with the user's OWN rhythm instead of a naive wall-clock line —
/// someone who starts at 10:00 shouldn't look "behind" at 08:00.
public struct IntradayProfile: Codable, Sendable, Equatable {
    /// Average cumulative fraction of a day's tokens reached by each local hour
    /// boundary; 25 entries, [0] = 0 … [24] = 1, monotonic non-decreasing.
    public let cumulativeFraction: [Double]
    /// Population std-dev of the per-day fractions at each hour (25 entries).
    public let dispersion: [Double]
    /// Number of complete days that informed the profile.
    public let dayCount: Int

    public init(cumulativeFraction: [Double], dispersion: [Double], dayCount: Int) {
        self.cumulativeFraction = cumulativeFraction
        self.dispersion = dispersion
        self.dayCount = dayCount
    }

    /// Build the profile from the last `days` COMPLETE local days before `now`'s
    /// day (today is excluded — it's the thing being forecast). Days below
    /// `minDayTokens` are noise and excluded. Returns nil below 3 qualifying days.
    public static func compute(
        records: [UsageRecord],
        now: Date,
        calendar: Calendar,
        days: Int = 14,
        minDayTokens: Int = 1_000_000
    ) -> IntradayProfile? {
        let today = calendar.startOfDay(for: now)
        guard let windowStart = calendar.date(byAdding: .day, value: -days, to: today) else { return nil }

        // Hourly token totals per qualifying past day.
        var hourlyByDay: [Date: [Int]] = [:]
        for record in records {
            let day = calendar.startOfDay(for: record.timestamp)
            guard day >= windowStart, day < today else { continue }
            let hour = calendar.component(.hour, from: record.timestamp)
            hourlyByDay[day, default: Array(repeating: 0, count: 24)][hour] += record.usage.totalTokens
        }

        let qualifying = hourlyByDay.values.filter { $0.reduce(0, +) >= minDayTokens }
        guard qualifying.count >= 3 else { return nil }

        // Each day's cumulative fraction at hour boundaries 0…24.
        let perDayFractions: [[Double]] = qualifying.map { hours in
            let total = Double(hours.reduce(0, +))
            var cum: [Double] = [0]
            var running = 0
            for h in 0..<24 {
                running += hours[h]
                cum.append(Double(running) / total)
            }
            return cum
        }

        let n = Double(perDayFractions.count)
        var mean = [Double](repeating: 0, count: 25)
        var std = [Double](repeating: 0, count: 25)
        for h in 0...24 {
            let values = perDayFractions.map { $0[h] }
            let m = values.reduce(0, +) / n
            mean[h] = m
            std[h] = (values.map { ($0 - m) * ($0 - m) }.reduce(0, +) / n).squareRoot()
        }
        return IntradayProfile(cumulativeFraction: mean, dispersion: std, dayCount: perDayFractions.count)
    }

    /// Linear interpolation over the hour boundaries at a fractional local hour.
    func interpolated(_ values: [Double], atHour hour: Double) -> Double {
        let clamped = min(max(hour, 0), 24)
        let lower = Int(clamped.rounded(.down))
        let upper = min(lower + 1, 24)
        let t = clamped - Double(lower)
        return values[lower] * (1 - t) + values[upper] * t
    }
}

/// "On pace for ~X tokens / $Y today" — projects today's total from tokens so
/// far and the user's own intraday rhythm. Deliberately refuses to guess when
/// the evidence is thin (see the gates in `compute`).
public struct DayEndForecast: Sendable, Equatable {
    public let projectedTokens: Int
    /// Pessimistic/optimistic band from the profile's day-to-day dispersion.
    public let lowTokens: Int
    public let highTokens: Int
    /// Today's blended cost rate applied to the projection (nil if cost unknown).
    public let projectedCost: Double?

    public init(projectedTokens: Int, lowTokens: Int, highTokens: Int, projectedCost: Double?) {
        self.projectedTokens = projectedTokens
        self.lowTokens = lowTokens
        self.highTokens = highTokens
        self.projectedCost = projectedCost
    }

    /// Fractions below this never divide (stops silly extrapolation just after
    /// midnight — at most 20× tokens-so-far).
    public static let fractionFloor = 0.05

    public static func compute(
        tokensToday: Int,
        costToday: Double?,
        now: Date,
        calendar: Calendar,
        profile: IntradayProfile?
    ) -> DayEndForecast? {
        guard let profile, tokensToday > 0 else { return nil }

        let hour = Double(calendar.component(.hour, from: now))
            + Double(calendar.component(.minute, from: now)) / 60
        let fraction = profile.interpolated(profile.cumulativeFraction, atHour: hour)
        // Early morning with (typically) nothing accumulated yet → a projection
        // would just be tokensToday × 20; stay silent instead.
        guard hour >= 8 || fraction >= 0.15 else { return nil }

        let f = max(fraction, fractionFloor)
        let sigma = profile.interpolated(profile.dispersion, atHour: hour)
        let projected = Int((Double(tokensToday) / f).rounded())
        let low = Int((Double(tokensToday) / min(1, f + sigma)).rounded())
        let high = Int((Double(tokensToday) / max(fractionFloor, f - sigma)).rounded())

        let cost = costToday.map { $0 / Double(tokensToday) * Double(projected) }
        return DayEndForecast(
            projectedTokens: projected,
            lowTokens: min(low, projected),
            highTokens: max(high, projected),
            projectedCost: cost)
    }
}
