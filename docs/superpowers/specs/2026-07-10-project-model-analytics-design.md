# Project × model analytics + plainer, %-driven charts — design

**Date:** 2026-07-10. User request (paraphrased): "add a breakdown of which
model I used how much, in which project, to the dashboard; add it to the
analytical charts; make the existing charts more analytical too — percentages,
and talk about it in simple terms."

## What already exists (don't rebuild)

`DailyAggregator.aggregate` already builds a project→model→tokens matrix
internally (`byProjectFamily: [String: [ModelFamily: TokenUsage]]`) purely to
total up each project's cost — then discards it. `UsageRecord` already carries
both `projectID` and `model` per record, and raw records are already retained
in `UsageStore`'s cache. So the new breakdown needs **no new cache schema and
no new persistence version** — it's a matter of surfacing data already
computed, plus the UI/analytics layer on top.

Existing "By model" and "By project" cards (`DashboardView.swift`) already
exist as separate, single-dimension views. This batch adds the *combined*
dimension and layers percentages onto what's already there.

## 1. Data layer (Kit)

- New struct `ProjectModelUsage` (`Sources/UsageMeterKit/Models/Aggregates.swift`,
  next to `ProjectUsage`/`ModelUsage`): `projectID: String`, `displayName: String`,
  `family: ModelFamily`, `usage: TokenUsage`, `estimatedCost: Double?`.
- New field on `ClaudeCodeStats`: `byProjectModel: [ProjectModelUsage]` — one
  entry per (project, model-family) pair with `usage.totalTokens > 0`, sorted by
  tokens desc (matches the existing `byModel`/`byProject` convention).
- `DailyAggregator.aggregate`: alongside where `dailyByModel` is built, map the
  existing `byProjectFamily` dict into `byProjectModel` entries (reuse the same
  `displayName` lookup already used for `byProject`). No new iteration over
  records needed — the matrix is already being built.
- **Scope caveat, stated honestly in the UI** (same pattern as today's "By
  project" card): **all-time only**, not scoped to the range picker. Per-day ×
  project × model isn't bucketed anywhere, and adding that dimension would
  meaningfully grow the on-disk cache for a menu-bar app, for a breakdown that's
  naturally a "where has my usage gone" question, not a "how did today trend"
  question — not worth the schema growth. Consistent with why "By project" is
  already labeled "· all time".

- New pure helper on `DashboardMetrics`:
  `projectModelBreakdown(_ byProjectModel: [ProjectModelUsage], topProjects: Int = 8) -> [ProjectBreakdown]`
  where `ProjectBreakdown` = `{ projectID, displayName, totalTokens, segments: [(family: ModelFamily, tokens: Int, percent: Double)] }`.
  - Projects ranked by total tokens desc, truncated to `topProjects` (mirrors
    the existing `byProjectCard`'s `.prefix(8)`).
  - Segments within a project sorted by tokens desc; `percent` = share of that
    project's total (0–100, sums to ~100 modulo rounding).
  - Empty input → `[]`.

## 2. New card: "Model mix by project"

Placed directly below the existing "By project" card (same section grouping,
so the single-dimension list and the combined breakdown sit next to each
other).

- **Form:** horizontal stacked `BarMark` per project — one bar per project (top
  8, same ranking as "By project"), segments sized by each model family's token
  share of that project.
- **Why stacked-bar over alternatives:** a heatmap trades away magnitude
  comparison across projects (color intensity reads worse than length for
  "which project used the most overall"); per-project donut charts scatter the
  percentages across up to 8 separate small charts, which is noisier and harder
  to compare project-to-project than segments sharing one length axis.
- **Interaction:** hovering a segment shows a tooltip — model name, token count,
  and % of that project's usage (reuses the existing hover-tooltip pattern from
  the history chart). A legend (swatch + model name) sits below the chart.
- **Caption:** plain language, e.g. "Which model you're using in each project."

### Color (ran through the dataviz skill's palette validator)

The app's theme ("Kiln") is deliberately monotone for data ink — one
plum/fuchsia hue for all single-series charts, violet reserved for interactive
chrome, green/amber/red reserved for status/quota escalation. A 5-way model
identity needs real categorical color, which this app doesn't have yet, so a
new fixed-order categorical set was derived and validated
(`node scripts/validate_palette.js`, `--pairs all` since which two families end
up adjacent in a given project's stack is data-dependent, not fixed):

| Family | Light | Dark |
|---|---|---|
| Opus | `#2a78d6` | `#3987e5` |
| Sonnet | `#1baf7a` | `#199e70` |
| Haiku | `#eda100` | `#c98500` |
| Fable | `#e87ba4` | `#c1467a` |
| Mythos | `#eb6834` | `#d95926` |
| Other/unknown | neutral system gray (`.secondary`-family), outside the hue rotation | same |

Passes lightness band, chroma floor, and CVD-separation checks; a couple of
adjacent pairs sit in the 8–12 "floor" band (legal only with secondary
encoding) — covered here by the always-visible legend + hover tooltips (never
color-alone). Order is fixed (`ModelFamily`'s declared case order) and never
re-cycled regardless of per-project ranking — color follows the model
identity, not its rank in a given bar.

New `Theme.modelColor(_ family: ModelFamily) -> Color` (in `Theme.swift`,
Kiln section) encodes this table; used only by this new card (existing
single-series charts keep `Theme.data`/`Theme.dataMuted` unchanged).

## 3. Percentages + plain language on existing cards

- **`byModelCard`:** add a "% of total" figure next to each model row (share of
  that range's total tokens across all models) — currently only shows absolute
  tokens + cost.
- **`byProjectCard`:** add a "% share" column (that project's share of all-time
  total tokens across all projects).
- **`weekdayCard`:** add a small caption comparing today's weekday average to
  the overall average, e.g. "Tuesdays run 18% above your usual" / "12% below" —
  computed from the existing `WeekdayAverage` list plus the overall mean
  (no new Kit function needed beyond a small view-local calc, since it's a
  single division over data already fetched).
- **Plain-language pass:** the outlier tooltip's `.help()` text currently reads
  "Days above your average + 2σ — statistical outliers in your usage." →
  reworded to "Days noticeably busier than usual for you." The visible label
  text ("N unusually heavy days") already reads fine and is unchanged.

## Error handling

- `projectModelBreakdown` on empty/zero data returns `[]`; the card is hidden
  entirely (same `if !byProjectModel.isEmpty` guard pattern as the existing
  by-model/by-project cards).
- Percent calculations guard divide-by-zero (0% shown, not NaN) — same pattern
  already used in `byModelCard`'s bar-width calc (`max(1, ...)`).

## Testing

- `DashboardMetricsTests`: new tests for `projectModelBreakdown` — percentages
  per project sum to ~100 (within rounding tolerance), top-N truncation,
  sort order (projects by total desc, segments by tokens desc), empty input.
- `DailyAggregatorTests`: new test asserting `byProjectModel` shape from a
  fixture spanning 2 projects × 2 models (values match hand-computed totals).
- Existing 144 tests stay green; both build variants (SwiftPM `make test` +
  the XcodeGen App Store target) unaffected since this is additive.

## Out of scope (deferred)

Per-day trend for the project×model breakdown (would need a new cache
dimension — deferred, matches the existing "all time" honesty label
precedent). Filtering the new card by the range picker. Exporting the
breakdown to CSV (existing CSV export stays per-day; this is a separate
all-time cut). GRDB migration.
