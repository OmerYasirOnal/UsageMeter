# Project × Model Analytics Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a "which model, in which project" breakdown to the UsageMeter dashboard, and layer percentages + plainer language onto the existing analytics cards.

**Architecture:** `DailyAggregator` already builds a project→model→tokens matrix internally (`byProjectFamily`) just to total per-project cost, then discards it — surface it as a new `byProjectModel: [ProjectModelUsage]` field on `ClaudeCodeStats` (Kit). A new pure `DashboardMetrics.projectModelBreakdown(_:)` turns that flat list into per-project segment breakdowns with percentages (Kit, unit-tested). The App layer gets a new `ProjectModelMixCard` view (stacked horizontal bar + legend + hover, Swift Charts) using a new fixed-order categorical color table on `Theme`, plus percentage additions to the existing "By model"/"By project"/"Weekly rhythm" cards.

**Tech Stack:** Swift 6, SwiftUI, Swift Charts, Swift Testing (`@Test`/`#expect`), SwiftPM.

## Global Constraints

- Dedup, cost model, and existing `ClaudeCodeStats` shape are untouched — this is purely additive (spec: "no new cache schema needed").
- The new breakdown is **all-time only**, not scoped to the range picker (spec: matches the existing "By project" card's honest "· all time" label; no per-day×project×model bucket is added).
- Model-identity color is the **only** departure from the app's single-data-hue "Kiln" theme; it must use the fixed-order, validated hex table below — never `Color.random`/hue-cycling, never reusing `Theme.accent` (chrome) or `Theme.ok`/`Theme.warning`/`Theme.danger` (status).
- All new Kit logic (aggregator + `DashboardMetrics` helper) is TDD'd with Swift Testing, following the existing test file conventions (`makeRecord(...)`, `TestTime.date(...)`, `utcCalendar()`).
- `swift test` (144 existing tests) must stay green throughout; each task ends with the suite passing.

---

### Task 1: Surface `byProjectModel` from `DailyAggregator`

**Files:**
- Modify: `Sources/UsageMeterKit/Models/Aggregates.swift:20-45` (add `ProjectModelUsage` struct after `ProjectUsage`), `Sources/UsageMeterKit/Models/Aggregates.swift:80-137` (add field to `ClaudeCodeStats`)
- Modify: `Sources/UsageMeterKit/ClaudeCode/DailyAggregator.swift:81-131`
- Test: `Tests/UsageMeterKitTests/DailyAggregatorTests.swift`

**Interfaces:**
- Produces: `public struct ProjectModelUsage: Codable, Sendable, Equatable { projectID: String, displayName: String, family: ModelFamily, usage: TokenUsage, estimatedCost: Double? }` and `ClaudeCodeStats.byProjectModel: [ProjectModelUsage]` (sorted by `(projectID, family.rawValue)` ascending, one entry per project×model pair with `usage.totalTokens > 0`).
- Consumes: existing `byProjectFamily: [String: [ModelFamily: TokenUsage]]` already computed in `DailyAggregator.aggregate` (no new iteration over records).

- [ ] **Step 1: Write the failing test**

Add to `Tests/UsageMeterKitTests/DailyAggregatorTests.swift`, right after `groupsByModelProjectAndDay()`:

```swift
    @Test func groupsByProjectAndModel() {
        let records = [
            makeRecord(id: "1", model: "opus", at: "2026-06-30T10:00:00.000Z", project: "A", output: 10),
            makeRecord(id: "2", model: "sonnet", at: "2026-06-30T10:00:00.000Z", project: "A", output: 20),
            makeRecord(id: "3", model: "opus", at: "2026-06-29T10:00:00.000Z", project: "B", output: 30)
        ]
        let stats = makeAggregator().aggregate(records: records, now: TestTime.date("2026-06-30T12:00:00.000Z"))
        #expect(stats.byProjectModel.count == 3)
        let aOpus = stats.byProjectModel.first { $0.projectID == "A" && $0.family == .opus }
        #expect(aOpus?.usage.totalTokens == 10)
        let aSonnet = stats.byProjectModel.first { $0.projectID == "A" && $0.family == .sonnet }
        #expect(aSonnet?.usage.totalTokens == 20)
        let bOpus = stats.byProjectModel.first { $0.projectID == "B" && $0.family == .opus }
        #expect(bOpus?.usage.totalTokens == 30)
    }
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `swift test --filter DailyAggregatorTests`
Expected: FAIL — `value of type 'ClaudeCodeStats' has no member 'byProjectModel'`

- [ ] **Step 3: Add `ProjectModelUsage` and the `byProjectModel` field**

In `Sources/UsageMeterKit/Models/Aggregates.swift`, insert right after the closing brace of `ProjectUsage` (after line 45, before the `DailyUsage` doc comment):

```swift
/// Usage + estimated cost for one (project, model family) pair — the
/// combined dimension "which model, in which project".
public struct ProjectModelUsage: Codable, Sendable, Equatable {
    public var projectID: String
    public var displayName: String
    public var family: ModelFamily
    public var usage: TokenUsage
    public var estimatedCost: Double?

    public init(
        projectID: String,
        displayName: String,
        family: ModelFamily,
        usage: TokenUsage = .zero,
        estimatedCost: Double? = nil
    ) {
        self.projectID = projectID
        self.displayName = displayName
        self.family = family
        self.usage = usage
        self.estimatedCost = estimatedCost
    }
}
```

Then in `ClaudeCodeStats` (same file), add the field to the property list (right after `public var byDay: [DailyUsage]`):

```swift
    public var byDay: [DailyUsage]
    /// (Project, model family) pairs — all time (no per-day bucket is kept
    /// for this triple; see docs/superpowers/specs/2026-07-10-project-model-analytics-design.md).
    public var byProjectModel: [ProjectModelUsage]
```

Add the matching init parameter + assignment (in the `init`, right after `byDay: [DailyUsage] = [],` and `self.byDay = byDay`):

```swift
        byDay: [DailyUsage] = [],
        byProjectModel: [ProjectModelUsage] = [],
```

```swift
        self.byDay = byDay
        self.byProjectModel = byProjectModel
```

- [ ] **Step 4: Populate `byProjectModel` in `DailyAggregator.aggregate`**

In `Sources/UsageMeterKit/ClaudeCode/DailyAggregator.swift`, right after the `dailyByModel` construction (after line 112, before `let blockBuilder = ...`), add:

```swift
        let projectModelUsages: [ProjectModelUsage] = byProjectFamily
            .flatMap { projectID, families in
                families.map { family, usage in
                    ProjectModelUsage(
                        projectID: projectID,
                        displayName: ProjectName.display(forSlug: projectID),
                        family: family,
                        usage: usage,
                        estimatedCost: calculator.cost(usage: usage, family: family))
                }
            }
            .sorted { ($0.projectID, $0.family.rawValue) < ($1.projectID, $1.family.rawValue) }
```

Then add `byProjectModel: projectModelUsages` to the returned `ClaudeCodeStats(...)` call, right after `dailyByModel: dailyByModel`:

```swift
            dailyByModel: dailyByModel,
            byProjectModel: projectModelUsages
        )
```

- [ ] **Step 5: Run the test to verify it passes**

Run: `swift test --filter DailyAggregatorTests`
Expected: PASS (all `DailyAggregatorTests` cases, including the new one)

- [ ] **Step 6: Run the full suite to confirm no regressions**

Run: `swift test`
Expected: PASS — all existing + new tests green

- [ ] **Step 7: Commit**

```bash
git add Sources/UsageMeterKit/Models/Aggregates.swift Sources/UsageMeterKit/ClaudeCode/DailyAggregator.swift Tests/UsageMeterKitTests/DailyAggregatorTests.swift
git commit -m "$(cat <<'EOF'
feat(kit): surface project×model usage from the aggregator

DailyAggregator already builds this matrix internally to total
per-project cost; expose it as ClaudeCodeStats.byProjectModel so the
dashboard can show which model was used in which project.
EOF
)"
```

---

### Task 2: `DashboardMetrics.projectModelBreakdown` pure helper

**Files:**
- Modify: `Sources/UsageMeterKit/Engine/DashboardMetrics.swift`
- Test: `Tests/UsageMeterKitTests/DashboardMetricsTests.swift`

**Interfaces:**
- Consumes: `ProjectModelUsage` (Task 1) — `{ projectID, displayName, family, usage, estimatedCost }`.
- Produces:
  ```swift
  public struct ProjectBreakdown: Sendable, Equatable, Identifiable {
      public struct Segment: Sendable, Equatable, Identifiable {
          public let family: ModelFamily
          public let tokens: Int
          public let percent: Double   // 0...100, share of this project's total
          public var id: ModelFamily { family }
      }
      public let projectID: String
      public let displayName: String
      public let totalTokens: Int
      public let segments: [Segment]  // sorted by tokens desc
      public var id: String { projectID }
  }
  public static func projectModelBreakdown(
      _ byProjectModel: [ProjectModelUsage], topProjects: Int = 8
  ) -> [ProjectBreakdown]
  ```
  Projects sorted by `totalTokens` desc, truncated to `topProjects`. Empty input → `[]`.

- [ ] **Step 1: Write the failing tests**

Add to `Tests/UsageMeterKitTests/DashboardMetricsTests.swift`, at the end of the `@Suite struct DashboardMetricsTests { ... }` body (before the final closing brace):

```swift

    // MARK: - Project × model breakdown

    @Test func projectModelBreakdownComputesPercentagesAndSortOrder() {
        let entries = [
            ProjectModelUsage(projectID: "A", displayName: "Proj A", family: .opus,
                              usage: TokenUsage(outputTokens: 300)),
            ProjectModelUsage(projectID: "A", displayName: "Proj A", family: .sonnet,
                              usage: TokenUsage(outputTokens: 100)),
            ProjectModelUsage(projectID: "B", displayName: "Proj B", family: .haiku,
                              usage: TokenUsage(outputTokens: 50))
        ]
        let breakdown = DashboardMetrics.projectModelBreakdown(entries)
        #expect(breakdown.count == 2)
        #expect(breakdown.first?.projectID == "A")   // A's total (400) > B's (50)
        #expect(breakdown.first?.totalTokens == 400)
        let segments = breakdown.first?.segments ?? []
        #expect(segments.count == 2)
        #expect(segments.first?.family == .opus)      // sorted desc by tokens
        #expect(segments.first?.percent.rounded() == 75)   // 300/400
        #expect(segments.last?.percent.rounded() == 25)    // 100/400
    }

    @Test func projectModelBreakdownTruncatesToTopProjects() {
        let entries = (0..<10).map { i in
            ProjectModelUsage(projectID: "P\(i)", displayName: "P\(i)", family: .opus,
                              usage: TokenUsage(outputTokens: 100 - i))
        }
        let breakdown = DashboardMetrics.projectModelBreakdown(entries, topProjects: 3)
        #expect(breakdown.count == 3)
        #expect(breakdown.map { $0.projectID } == ["P0", "P1", "P2"])
    }

    @Test func projectModelBreakdownEmptyForNoData() {
        #expect(DashboardMetrics.projectModelBreakdown([]).isEmpty)
    }
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --filter DashboardMetricsTests`
Expected: FAIL — `type 'DashboardMetrics' has no member 'projectModelBreakdown'`

- [ ] **Step 3: Implement `ProjectBreakdown` + `projectModelBreakdown`**

In `Sources/UsageMeterKit/Engine/DashboardMetrics.swift`, add the new struct right after the `WeekdayAverage` struct (after line 62, before the `DashboardRange` enum):

```swift
/// One project's model mix — "which model, in which project" — with each
/// segment's share of that project's total tokens.
public struct ProjectBreakdown: Sendable, Equatable, Identifiable {
    public struct Segment: Sendable, Equatable, Identifiable {
        public let family: ModelFamily
        public let tokens: Int
        /// 0...100, this family's share of the project's total.
        public let percent: Double
        public var id: ModelFamily { family }

        public init(family: ModelFamily, tokens: Int, percent: Double) {
            self.family = family
            self.tokens = tokens
            self.percent = percent
        }
    }

    public let projectID: String
    public let displayName: String
    public let totalTokens: Int
    public let segments: [Segment]
    public var id: String { projectID }

    public init(projectID: String, displayName: String, totalTokens: Int, segments: [Segment]) {
        self.projectID = projectID
        self.displayName = displayName
        self.totalTokens = totalTokens
        self.segments = segments
    }
}
```

Then add the function inside `enum DashboardMetrics { ... }`, right after `modelUsage(...)` (after line 212, before `anomalousDays`):

```swift
    /// "Which model, in which project" — all-time, top `topProjects` by total
    /// tokens desc; each project's segments sorted by tokens desc with each
    /// segment's percentage share of that project's total.
    public static func projectModelBreakdown(
        _ byProjectModel: [ProjectModelUsage], topProjects: Int = 8
    ) -> [ProjectBreakdown] {
        guard !byProjectModel.isEmpty else { return [] }
        var byProject: [String: (displayName: String, tokensByFamily: [ModelFamily: Int])] = [:]
        for entry in byProjectModel {
            var bucket = byProject[entry.projectID] ?? (entry.displayName, [:])
            bucket.tokensByFamily[entry.family, default: 0] += entry.usage.totalTokens
            byProject[entry.projectID] = bucket
        }
        return byProject
            .map { projectID, bucket -> ProjectBreakdown in
                let total = bucket.tokensByFamily.values.reduce(0, +)
                let segments = bucket.tokensByFamily
                    .map { family, tokens in
                        ProjectBreakdown.Segment(
                            family: family, tokens: tokens,
                            percent: total > 0 ? Double(tokens) / Double(total) * 100 : 0)
                    }
                    .sorted { $0.tokens > $1.tokens }
                return ProjectBreakdown(projectID: projectID, displayName: bucket.displayName,
                                        totalTokens: total, segments: segments)
            }
            .sorted { $0.totalTokens > $1.totalTokens }
            .prefix(topProjects)
            .map { $0 }
    }
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --filter DashboardMetricsTests`
Expected: PASS

- [ ] **Step 5: Run the full suite**

Run: `swift test`
Expected: PASS

- [ ] **Step 6: Commit**

```bash
git add Sources/UsageMeterKit/Engine/DashboardMetrics.swift Tests/UsageMeterKitTests/DashboardMetricsTests.swift
git commit -m "$(cat <<'EOF'
feat(kit): add DashboardMetrics.projectModelBreakdown

Pure transform from the raw project×model list to per-project model
segments with percentage shares — the data the new dashboard card renders.
EOF
)"
```

---

### Task 3: Fixed-order categorical color table for model identity

**Files:**
- Modify: `Sources/UsageMeter/App/Theme.swift`

**Interfaces:**
- Consumes: `ModelFamily` (Kit enum: `.opus`, `.sonnet`, `.haiku`, `.fable`, `.mythos`, `.unknown`).
- Produces: `Theme.modelColor(_ family: ModelFamily) -> Color`, used by Task 4/5.

No dedicated automated test (SwiftUI `Color` values aren't meaningfully unit-testable in this headless test target — same as the rest of `Theme.swift`, which has no tests). Verified by compiling and by the visual check in Task 5.

- [ ] **Step 1: Add the categorical color table**

In `Sources/UsageMeter/App/Theme.swift`, add this at the end of `enum Theme { ... }`, right before the closing brace (after the `cardCorner` constant):

```swift

    /// Fixed-order categorical color for model-family IDENTITY (which model),
    /// not magnitude — the one deliberate departure from Kiln's single data
    /// hue. Order is fixed (ModelFamily's declared case order) and never
    /// re-cycled by a bar's rank; validated for CVD-safe adjacency via the
    /// dataviz skill's palette checker (worst all-pairs floor ~8-12 ΔE, legal
    /// because segments always ship with a visible legend + hover tooltip —
    /// never color-alone). See
    /// docs/superpowers/specs/2026-07-10-project-model-analytics-design.md.
    static func modelColor(_ family: ModelFamily) -> Color {
        switch family {
        case .opus: return Color(light: 0x2A78D6, dark: 0x3987E5)
        case .sonnet: return Color(light: 0x1BAF7A, dark: 0x199E70)
        case .haiku: return Color(light: 0xEDA100, dark: 0xC98500)
        case .fable: return Color(light: 0xE87BA4, dark: 0xC1467A)
        case .mythos: return Color(light: 0xEB6834, dark: 0xD95926)
        case .unknown: return Color(nsColor: .systemGray)
        }
    }
```

- [ ] **Step 2: Build to verify it compiles**

Run: `swift build`
Expected: Build succeeds with no errors.

- [ ] **Step 3: Commit**

```bash
git add Sources/UsageMeter/App/Theme.swift
git commit -m "$(cat <<'EOF'
feat(theme): add validated categorical color table for model identity

Sonnet/Opus/Haiku/Fable/Mythos each get a fixed, CVD-checked hue for the
new project×model chart — the only departure from Kiln's single-hue data
ink, since model IDENTITY (not magnitude) needs real categorical color.
EOF
)"
```

---

### Task 4: `Formatting.percent` helper

**Files:**
- Modify: `Sources/UsageMeter/App/Formatting.swift`

**Interfaces:**
- Produces: `Formatting.percent(_ value: Double) -> String` — e.g. `Formatting.percent(74.6) == "75%"`.

No dedicated test target covers `Formatting` (App-module presentation helpers, same as the rest of the file) — verified by compiling and by visual checks in Tasks 5-6.

- [ ] **Step 1: Add the helper**

In `Sources/UsageMeter/App/Formatting.swift`, add right after `axisTokens(_:)` (after line 53, before `money(_:currency:)`):

```swift

    /// A share like "34%" — rounded to the nearest whole percent (a UI where
    /// exact-to-the-tenth wouldn't change the takeaway).
    static func percent(_ value: Double) -> String {
        "\(Int(value.rounded()))%"
    }
```

- [ ] **Step 2: Build to verify it compiles**

Run: `swift build`
Expected: Build succeeds with no errors.

- [ ] **Step 3: Commit**

```bash
git add Sources/UsageMeter/App/Formatting.swift
git commit -m "feat(format): add Formatting.percent for share figures"
```

---

### Task 5: New `ProjectModelMixCard` view

**Files:**
- Create: `Sources/UsageMeter/Dashboard/ProjectModelMixCard.swift`

**Interfaces:**
- Consumes: `ProjectBreakdown`/`ProjectBreakdown.Segment` (Task 2), `Theme.modelColor(_:)` (Task 3), `Formatting.tokens(_:)`/`Formatting.percent(_:)` (existing/Task 4), `Formatting.axisTokens(_:)`, `Theme.corner`/`.card()` (existing `CardBackground` modifier).
- Produces: `struct ProjectModelMixCard: View { let breakdown: [ProjectBreakdown]; ... }` — a self-contained card (mirrors `ActivityGrid`/`TeamCard`'s pattern of a plain data-driven `View` struct in `Sources/UsageMeter/Dashboard/`), consumed by `DashboardView` in Task 6.

- [ ] **Step 1: Create the file**

```swift
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
```

- [ ] **Step 2: Build to verify it compiles**

Run: `swift build`
Expected: Build succeeds with no errors. (The view isn't referenced from `DashboardView` yet, so this only proves the file itself is well-formed.)

- [ ] **Step 3: Commit**

```bash
git add Sources/UsageMeter/Dashboard/ProjectModelMixCard.swift
git commit -m "$(cat <<'EOF'
feat(dashboard): add ProjectModelMixCard view

Stacked horizontal bar per project, segments by model family, with a
hover tooltip and legend. Not yet wired into DashboardView.
EOF
)"
```

---

### Task 6: Wire `ProjectModelMixCard` into the dashboard + demo data

**Files:**
- Modify: `Sources/UsageMeter/Dashboard/DashboardView.swift:44-51`
- Modify: `Sources/UsageMeter/App/DemoData.swift`

**Interfaces:**
- Consumes: `DashboardMetrics.projectModelBreakdown(_:)` (Task 2), `ProjectModelMixCard` (Task 5), `ClaudeCodeStats.byProjectModel` (Task 1).

- [ ] **Step 1: Wire the card into `DashboardView.body`**

In `Sources/UsageMeter/Dashboard/DashboardView.swift`, change:

```swift
                if !model.snapshot.claudeCode.byModel.isEmpty { byModelCard }
                if !model.snapshot.claudeCode.byProject.isEmpty { byProjectCard }
                TeamCard()
```

to:

```swift
                if !model.snapshot.claudeCode.byModel.isEmpty { byModelCard }
                if !model.snapshot.claudeCode.byProject.isEmpty { byProjectCard }
                if !model.snapshot.claudeCode.byProjectModel.isEmpty {
                    ProjectModelMixCard(breakdown: DashboardMetrics.projectModelBreakdown(
                        model.snapshot.claudeCode.byProjectModel))
                }
                TeamCard()
```

- [ ] **Step 2: Build to verify it compiles**

Run: `swift build`
Expected: Build succeeds with no errors.

- [ ] **Step 3: Add demo data so `make demo` shows the new card**

In `Sources/UsageMeter/App/DemoData.swift`, right after the existing `byProject` array is built (after the closing `]` of `let byProject = [...]`, before the `return ClaudeCodeStats(...)` call), add:

```swift
        func projectModel(_ name: String, _ family: ModelFamily, _ u: TokenUsage) -> ProjectModelUsage {
            ProjectModelUsage(projectID: name, displayName: name, family: family, usage: u,
                              estimatedCost: calc.cost(usage: u, family: family))
        }
        let byProjectModel = [
            projectModel("usage-meter", .opus, TokenUsage(cacheReadTokens: 620_000_000, outputTokens: 8_000_000)),
            projectModel("usage-meter", .sonnet, TokenUsage(cacheReadTokens: 300_000_000, outputTokens: 3_500_000)),
            projectModel("usage-meter", .haiku, TokenUsage(cacheReadTokens: 60_000_000, outputTokens: 500_000)),
            projectModel("web-platform", .sonnet, TokenUsage(cacheReadTokens: 420_000_000, outputTokens: 5_200_000)),
            projectModel("web-platform", .fable, TokenUsage(cacheReadTokens: 100_000_000, outputTokens: 1_200_000)),
            projectModel("data-pipeline", .opus, TokenUsage(cacheReadTokens: 180_000_000, outputTokens: 2_400_000)),
            projectModel("data-pipeline", .haiku, TokenUsage(cacheReadTokens: 60_000_000, outputTokens: 700_000)),
            projectModel("ios-client", .sonnet, TokenUsage(cacheReadTokens: 90_000_000, outputTokens: 1_200_000)),
            projectModel("ios-client", .mythos, TokenUsage(cacheReadTokens: 20_000_000, outputTokens: 300_000)),
            projectModel("infra-scripts", .haiku, TokenUsage(cacheReadTokens: 60_000_000, outputTokens: 820_000))
        ]
```

Then add `byProjectModel: byProjectModel` to the returned `ClaudeCodeStats(...)` call, right after `byProject: byProject,`:

```swift
            byProject: byProject,
            byProjectModel: byProjectModel,
```

- [ ] **Step 4: Build to verify it compiles**

Run: `swift build`
Expected: Build succeeds with no errors.

- [ ] **Step 5: Run the full test suite**

Run: `swift test`
Expected: PASS — all existing + new tests green.

- [ ] **Step 6: Visually verify the new card**

Run: `make demo`
Expected: the app launches with `USAGEMETER_DEMO=1`. Click the menu-bar gauge → "Dashboard". Confirm:
- A "Model mix by project" card appears below "By project", showing 5 projects as horizontal stacked bars.
- Hovering a segment shows a caption with project · model · tokens (%).
- The legend below shows only the model families actually present (Opus, Sonnet, Haiku, Fable, Mythos — no "Other").
- Colors are distinguishable in both light and dark mode (toggle via Settings → Appearance, or System Settings dark mode).

If anything looks wrong (label collisions, overlapping bars, a segment miscolored), fix it before moving on — this is real visual output, not just a compile check.

- [ ] **Step 7: Commit**

```bash
git add Sources/UsageMeter/Dashboard/DashboardView.swift Sources/UsageMeter/App/DemoData.swift
git commit -m "$(cat <<'EOF'
feat(dashboard): wire in the model-mix-by-project card

Also adds demo data so `make demo` / screenshot capture shows the new
card with realistic-looking sample values.
EOF
)"
```

---

### Task 7: Percentages on "By model" and "By project"

**Files:**
- Modify: `Sources/UsageMeter/Dashboard/DashboardView.swift:479-541` (`byModelCard`, `byProjectCard`)

**Interfaces:**
- Consumes: `Formatting.percent(_:)` (Task 4).

- [ ] **Step 1: Add "% of total" to `byModelCard`**

In `Sources/UsageMeter/Dashboard/DashboardView.swift`, change:

```swift
    private var byModelCard: some View {
        // Range-coherent: follows the Usage History range picker (all-time list
        // was silently shown for every range before).
        let models = range == .all
            ? model.snapshot.claudeCode.byModel
            : DashboardMetrics.modelUsage(model.snapshot.claudeCode.dailyByModel, range: range)
        let maxTokens = max(1, models.map { $0.usage.totalTokens }.max() ?? 1)
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Text("By model").font(.title3.bold())
                Text(range == .all ? "· all time" : "· last \(range.label.lowercased())")
                    .font(.caption).foregroundStyle(.secondary)
            }
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
```

to:

```swift
    private var byModelCard: some View {
        // Range-coherent: follows the Usage History range picker (all-time list
        // was silently shown for every range before).
        let models = range == .all
            ? model.snapshot.claudeCode.byModel
            : DashboardMetrics.modelUsage(model.snapshot.claudeCode.dailyByModel, range: range)
        let maxTokens = max(1, models.map { $0.usage.totalTokens }.max() ?? 1)
        let totalTokens = models.reduce(0) { $0 + $1.usage.totalTokens }
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Text("By model").font(.title3.bold())
                Text(range == .all ? "· all time" : "· last \(range.label.lowercased())")
                    .font(.caption).foregroundStyle(.secondary)
            }
            ForEach(models) { m in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(m.family.displayName).font(.callout.weight(.medium))
                        Spacer()
                        Text(Formatting.percent(totalTokens > 0
                                                 ? Double(m.usage.totalTokens) / Double(totalTokens) * 100 : 0))
                            .foregroundStyle(.secondary)
                            .frame(width: 46, alignment: .trailing).monospacedDigit()
                        Text(Formatting.tokens(m.usage.totalTokens)).monospacedDigit()
                            .frame(width: 64, alignment: .trailing)
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
```

- [ ] **Step 2: Add a "%" column to `byProjectCard`**

In the same file, change:

```swift
    private var byProjectCard: some View {
        let projects = Array(model.snapshot.claudeCode.byProject.prefix(8))
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Text("By project").font(.title3.bold())
                // Honest label: this table is NOT range-scoped (per-project
                // per-day buckets aren't kept — costs need the model split).
                Text("· all time").font(.caption).foregroundStyle(.secondary)
            }
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
```

to:

```swift
    private var byProjectCard: some View {
        let allProjects = model.snapshot.claudeCode.byProject
        let projects = Array(allProjects.prefix(8))
        let totalTokens = allProjects.reduce(0) { $0 + $1.usage.totalTokens }
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Text("By project").font(.title3.bold())
                // Honest label: this table is NOT range-scoped (per-project
                // per-day buckets aren't kept — costs need the model split).
                Text("· all time").font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                Text("Project").frame(maxWidth: .infinity, alignment: .leading)
                Text("Sessions").frame(width: 70, alignment: .trailing)
                Text("%").frame(width: 46, alignment: .trailing)
                Text("Tokens").frame(width: 80, alignment: .trailing)
                Text("Cost").frame(width: 80, alignment: .trailing)
            }
            .font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
            ForEach(projects) { p in
                HStack {
                    Text(p.displayName).lineLimit(1).truncationMode(.middle)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text("\(p.sessionCount)").frame(width: 70, alignment: .trailing)
                    Text(Formatting.percent(totalTokens > 0
                                             ? Double(p.usage.totalTokens) / Double(totalTokens) * 100 : 0))
                        .foregroundStyle(.secondary)
                        .frame(width: 46, alignment: .trailing)
                    Text(Formatting.tokens(p.usage.totalTokens)).frame(width: 80, alignment: .trailing)
                    Text(Formatting.cost(p.estimatedCost)).foregroundStyle(.secondary)
                        .frame(width: 80, alignment: .trailing)
                }
                .font(.callout).monospacedDigit()
            }
        }
        .card()
    }
```

- [ ] **Step 3: Build to verify it compiles**

Run: `swift build`
Expected: Build succeeds with no errors.

- [ ] **Step 4: Run the full test suite**

Run: `swift test`
Expected: PASS

- [ ] **Step 5: Visually verify**

Run: `make demo`, open Dashboard, confirm:
- "By model" rows now show a `%` figure before the token count, and all three trailing columns (%, tokens, cost) line up cleanly across rows.
- "By project" now has a `%` column between Sessions and Tokens, with values that look like plausible shares (they don't all need to sum to exactly 100% on screen since only the top 8 of possibly more projects are shown — but each shown value should look like a sane share of the all-time total).

- [ ] **Step 6: Commit**

```bash
git add Sources/UsageMeter/Dashboard/DashboardView.swift
git commit -m "feat(dashboard): add % of total to the by-model and by-project cards"
```

---

### Task 8: Weekday comparison caption + plainer outlier tooltip

**Files:**
- Modify: `Sources/UsageMeter/Dashboard/DashboardView.swift:377-449` (`weekdayCard`, `activityCard`)

**Interfaces:** none new — this task only touches `DashboardView`'s existing private view builders.

- [ ] **Step 1: Add a today-vs-average caption to `weekdayCard`**

In `Sources/UsageMeter/Dashboard/DashboardView.swift`, change:

```swift
    @ViewBuilder
    private func weekdayCard(_ allPoints: [DailyPoint]) -> some View {
        let averages = DashboardMetrics.weekdayAverages(allPoints)
        if averages.contains(where: { $0.averageTokens > 0 }) {
            let todayWeekday = Calendar.current.component(.weekday, from: Date())
            let symbols = Calendar.current.shortWeekdaySymbols // index 0 = Sunday
            // Present in the user's week order (firstWeekday-based).
            let ordered = orderedByFirstWeekday(averages)
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Weekly rhythm").font(.title3.bold())
                    Text("Average tokens by weekday · last 12 weeks").font(.caption).foregroundStyle(.secondary)
                }
```

to:

```swift
    @ViewBuilder
    private func weekdayCard(_ allPoints: [DailyPoint]) -> some View {
        let averages = DashboardMetrics.weekdayAverages(allPoints)
        if averages.contains(where: { $0.averageTokens > 0 }) {
            let todayWeekday = Calendar.current.component(.weekday, from: Date())
            let symbols = Calendar.current.shortWeekdaySymbols // index 0 = Sunday
            // Present in the user's week order (firstWeekday-based).
            let ordered = orderedByFirstWeekday(averages)
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Weekly rhythm").font(.title3.bold())
                    Text("Average tokens by weekday · last 12 weeks").font(.caption).foregroundStyle(.secondary)
                    if let caption = weekdayComparisonCaption(averages, todayWeekday: todayWeekday) {
                        Text(caption).font(.caption).foregroundStyle(.secondary)
                    }
                }
```

Then add a new private helper right after `orderedByFirstWeekday(_:)` (after line 424):

```swift
    /// "Today runs 18% above your usual" / "12% below your usual" — plain
    /// comparison of today's weekday average against the overall average
    /// across all seven weekdays. Nil when there's no usable baseline.
    private func weekdayComparisonCaption(_ averages: [WeekdayAverage], todayWeekday: Int) -> String? {
        guard let todayAverage = averages.first(where: { $0.weekday == todayWeekday })?.averageTokens else {
            return nil
        }
        let overall = Double(averages.reduce(0) { $0 + $1.averageTokens }) / Double(averages.count)
        guard overall > 0 else { return nil }
        let diff = (Double(todayAverage) - overall) / overall * 100
        if abs(diff) < 5 { return "About your usual day" }
        let direction = diff >= 0 ? "above" : "below"
        return "Today runs \(Formatting.percent(abs(diff))) \(direction) your usual"
    }
```

- [ ] **Step 2: Simplify the outlier tooltip's plain-language text**

In the same file, change:

```swift
                .font(.caption).foregroundStyle(.secondary)
                .help("Days above your average + 2σ — statistical outliers in your usage.")
```

(inside `activityCard`) to:

```swift
                .font(.caption).foregroundStyle(.secondary)
                .help("Days noticeably busier than usual for you.")
```

- [ ] **Step 3: Build to verify it compiles**

Run: `swift build`
Expected: Build succeeds with no errors.

- [ ] **Step 4: Run the full test suite**

Run: `swift test`
Expected: PASS

- [ ] **Step 5: Visually verify**

Run: `make demo`, open Dashboard, confirm:
- "Weekly rhythm" now shows a third caption line like "Today runs 18% above your usual" (or "About your usual day"/"...below...", depending on the demo data's current weekday).
- Hovering the "N unusually heavy days" label under "Activity" shows the new plain-language tooltip text (no "σ").

- [ ] **Step 6: Commit**

```bash
git add Sources/UsageMeter/Dashboard/DashboardView.swift
git commit -m "feat(dashboard): plain-language weekday comparison + simplify outlier tooltip"
```

---

## Final check

- [ ] Run `swift test` one more time from the repo root — expect the full suite (144 existing + 4 new: 1 aggregator test + 3 `projectModelBreakdown` tests) green.
- [ ] Run `make app` to confirm the release-assembled `.app` still builds cleanly (separate from `swift build`'s debug build).
- [ ] Update `docs/STATUS.md`'s TL;DR if this is being shipped as part of the next release (out of scope for this plan — flag it for the user rather than editing STATUS.md speculatively).
