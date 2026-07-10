import SwiftUI
import Charts
import UsageMeterKit

/// Stacked horizontal bars: one row per project, segments sized by each
/// model family's share of that project's tokens — "which model, in which
/// project" at a glance. All-time (no per-day×project×model bucket is kept;
/// see docs/superpowers/specs/2026-07-10-project-model-analytics-design.md).
struct ProjectModelMixCard: View {
    let breakdown: [ProjectBreakdown]
    @State private var hovered: (project: ProjectBreakdown, segment: ProjectBreakdown.Segment)?

    /// Legend order: fixed declared `ModelFamily` order, only families
    /// actually present in this data.
    private var presentFamilies: [ModelFamily] {
        let present = Set(breakdown.flatMap { $0.segments.map(\.family) })
        return ModelFamily.allCases.filter { present.contains($0) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 1) {
                Text("Model mix by project").font(.title3.bold())
                Text("Which model you're using in each project · all time")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Chart(breakdown) { project in
                ForEach(project.segments) { segment in
                    BarMark(
                        x: .value("Tokens", segment.tokens),
                        y: .value("Project", project.displayName)
                    )
                    .foregroundStyle(Theme.modelColor(segment.family))
                    .cornerRadius(3)
                }
            }
            .chartOverlay { proxy in
                GeometryReader { geo in
                    Rectangle().fill(.clear).contentShape(Rectangle())
                        .onContinuousHover { phase in
                            switch phase {
                            case .active(let location):
                                hovered = nearestSegment(at: location, proxy: proxy, geo: geo)
                            case .ended:
                                hovered = nil
                            }
                        }
                }
            }
            .chartXAxis {
                AxisMarks { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let i = value.as(Int.self) { Text(Formatting.axisTokens(i)).font(.caption2) }
                    }
                }
            }
            .frame(height: CGFloat(breakdown.count) * 28 + 20)
            if let hovered {
                hoverCaption(hovered.project, hovered.segment)
            } else {
                Color.clear.frame(height: 14)
            }
            legend
        }
        .card()
    }

    private var legend: some View {
        HStack(spacing: 12) {
            ForEach(presentFamilies, id: \.self) { family in
                HStack(spacing: 5) {
                    RoundedRectangle(cornerRadius: 2).fill(Theme.modelColor(family)).frame(width: 10, height: 10)
                    Text(family.displayName).font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private func hoverCaption(_ project: ProjectBreakdown, _ segment: ProjectBreakdown.Segment) -> some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 2).fill(Theme.modelColor(segment.family)).frame(width: 10, height: 10)
            Text("\(project.displayName) · \(segment.family.displayName): "
                 + "\(Formatting.tokens(segment.tokens)) (\(Formatting.percent(segment.percent)))")
        }
        .font(.caption).foregroundStyle(.secondary)
    }

    /// Map a hover location to the project row (categorical y) and the
    /// stacked segment under the pointer (cumulative x within that row).
    private func nearestSegment(at location: CGPoint, proxy: ChartProxy, geo: GeometryProxy)
        -> (project: ProjectBreakdown, segment: ProjectBreakdown.Segment)? {
        let plotFrame = geo[proxy.plotFrame!]
        guard plotFrame.contains(location) else { return nil }
        let x = location.x - plotFrame.minX
        let y = location.y - plotFrame.minY
        guard let projectName: String = proxy.value(atY: y),
              let project = breakdown.first(where: { $0.displayName == projectName }),
              let tokenX: Int = proxy.value(atX: x)
        else { return nil }
        var cumulative = 0
        for segment in project.segments {
            cumulative += segment.tokens
            if tokenX <= cumulative { return (project, segment) }
        }
        return project.segments.last.map { (project, $0) }
    }
}
