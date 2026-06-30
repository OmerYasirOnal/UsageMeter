import SwiftUI
import UsageMeterKit

/// A GitHub-style contribution heatmap of daily Claude Code token usage (last 12 months).
struct ActivityGrid: View {
    let points: [DailyPoint]
    var weeks: Int = 53   // ~12 months

    private let calendar = Calendar.current
    private let cell: CGFloat = 11
    private let spacing: CGFloat = 3

    var body: some View {
        let lookup = tokensByDay()                 // built once per render
        let columns = buildColumns()
        let maxTokens = max(1, points.map(\.tokens).max() ?? 1)

        VStack(alignment: .leading, spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: spacing) {
                    ForEach(Array(columns.enumerated()), id: \.offset) { _, week in
                        VStack(spacing: spacing) {
                            ForEach(0..<7, id: \.self) { row in
                                cell(week[row], maxTokens: maxTokens, lookup: lookup)
                            }
                        }
                    }
                }
            }
            HStack(spacing: 6) {
                Text("Less").font(.caption2).foregroundStyle(.secondary)
                ForEach(0..<5, id: \.self) { level in
                    RoundedRectangle(cornerRadius: 2).fill(color(for: level)).frame(width: 10, height: 10)
                }
                Text("More").font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func cell(_ date: Date?, maxTokens: Int, lookup: [Date: Int]) -> some View {
        if let date {
            let tokens = lookup[calendar.startOfDay(for: date)] ?? 0
            RoundedRectangle(cornerRadius: 2.5)
                .fill(color(for: level(tokens, max: maxTokens)))
                .frame(width: cell, height: cell)
                .help(tokens > 0
                      ? "\(Formatting.tokens(tokens)) on \(date.formatted(.dateTime.month(.abbreviated).day().year()))"
                      : "No usage on \(date.formatted(.dateTime.month(.abbreviated).day().year()))")
        } else {
            Color.clear.frame(width: cell, height: cell)
        }
    }

    private func tokensByDay() -> [Date: Int] {
        Dictionary(points.map { (calendar.startOfDay(for: $0.date), $0.tokens) },
                   uniquingKeysWith: +)
    }

    /// Build `weeks` columns of 7 days each, aligned so each column starts on the
    /// week's first weekday; leading padding before the first day is `nil`.
    private func buildColumns() -> [[Date?]] {
        let today = calendar.startOfDay(for: Date())
        let total = weeks * 7
        guard let start = calendar.date(byAdding: .day, value: -(total - 1), to: today) else { return [] }

        let firstWeekday = calendar.firstWeekday
        let leadingPad = ((calendar.component(.weekday, from: start) - firstWeekday) + 7) % 7

        var slots: [Date?] = Array(repeating: nil, count: leadingPad)
        for offset in 0..<total {
            slots.append(calendar.date(byAdding: .day, value: offset, to: start))
        }
        while slots.count % 7 != 0 { slots.append(nil) }

        return stride(from: 0, to: slots.count, by: 7).map { Array(slots[$0..<$0 + 7]) }
    }

    private func level(_ tokens: Int, max: Int) -> Int {
        guard tokens > 0, max > 0 else { return 0 }
        switch Double(tokens) / Double(max) {
        case ..<0.25: return 1
        case ..<0.5: return 2
        case ..<0.75: return 3
        default: return 4
        }
    }

    private func color(for level: Int) -> Color {
        switch level {
        case 1: return Theme.accent.opacity(0.30)
        case 2: return Theme.accent.opacity(0.52)
        case 3: return Theme.accent.opacity(0.76)
        case 4: return Theme.accent
        default: return Color.primary.opacity(0.07)
        }
    }
}
