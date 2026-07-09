# Purple identity, menu-bar dynamic gauge, drop API value, Weekly Fable — design

**Date:** 2026-07-09 · **Status:** approved by Yasir · **Scope:** app-wide visual
identity + menu-bar glyph + popover glance + Source A decoding. Four independent
workstreams, one spec because they touch the same surface area (`Theme.swift`,
`MenuBarLabel`, `MenuBarContentView`, `AccountUsageDecoder`).

## Goal

Feedback on the current popover (screenshot, 2026-07-09): the "API value" line
still feels like clutter on the glance surface, the Kiln teal/terracotta identity
should become purple everywhere including the app icon, the menu-bar glyph should
be a genuinely dynamic filling gauge (not a static SF Symbol) while staying narrow,
and Fable 5 — which already has its own pricing tier in Source B — should also get
its own weekly-limit row from the account (Source A), the way Opus already does.

## 1. Drop "API value" from the popover glance

- Remove the "API value" `metric(...)` call and its tooltip from
  `MenuBarContentView.claudeCodeSection` (`Sources/UsageMeter/MenuBar/MenuBarContentView.swift`,
  the `HStack` around today's "Tokens" metric).
- The "N sessions · all-time ≈ …" caption currently branches on
  `model.settings.showApiValue` to show either total cost or total tokens — always
  show total tokens now (drop the branch).
- Remove the now-dead `showApiValue` setting: its `@AppStorage`/property in
  `AppSettings`, and its toggle row in `SettingsView`.
- **Scope: popover glance only.** The Dashboard window's detailed cost/Insights
  cards are unchanged — that's an opt-in deep view, not the glance surface the
  feedback was about.
- `Formatting.cost` / `todayEstimatedCost` / `totalEstimatedCost` stay on
  `UsageSnapshot` (still used by Dashboard) — nothing removed from Source B math,
  only from this one popover view.

## 2. Purple identity ("Kiln" duotone stays, hue moves to purple)

Keep the existing chrome-vs-data duotone *structure* (it's why Kiln passed its
5-lens CVD review) — swap both hues into the purple family instead of one flat
color, so chrome and data ink stay distinguishable from each other:

- `Theme.accent` (chrome: buttons, links, `.tint`, selection) → violet.
  Proposed: light `0x6D28D9`, dark `0xA78BFA`.
- `Theme.accentSoft` → light `0xEDE4FB`, dark `0x2C1F47`.
- `Theme.data` (data ink: chart bars, heatmap, gauge brand mark) → fuchsia/plum,
  a distinct hue from accent so they never visually collide (e.g. header icon next
  to header buttons). Proposed: light `0x86198F`, dark `0xE879F9`.
- `Theme.dataMuted` → light `0xA9779A`, dark `0xC79BC0`.
- `Theme.chartTop` / `Theme.chartBottom` (usage-history bar gradient) → shift into
  the same fuchsia/plum ramp as `data`.
- `Theme.heat` (4-level heatmap ramp) → reflow to a purple ramp (currently
  terracotta), same light/dark-pair structure, same 4 opaque steps.
- `Theme.ok` / `Theme.warning` / `Theme.danger` (semantic escalation, session %
  ramp) **unchanged** — these are universal status colors, not brand identity;
  changing them was never requested and would hurt at-a-glance severity reading.
- **App icon included.** `Scripts/icon/render.swift`'s terracotta trio
  (`coralTop`/`coralMid`/`coralBottom`) moves to the same violet/fuchsia pair used
  above, keeping the icon and in-app "gaugefill" mark visually the same family.
  Regenerate via `make icon`. Follow-up (tracked, not blocking this spec): README
  and App Store screenshots embed the old Kiln colors and should be recaptured —
  file as a TODO in `docs/STATUS.md`, not required for this implementation pass.
- Exact hex values above are a starting proposal, not final — verify WCAG contrast
  (chrome-on-background, numerals-on-card) and eyeball CVD legibility once
  rendered; nudge shades if a pairing reads too dark/washed, same latitude the
  original Kiln pass used.

## 3. Menu-bar dynamic filling gauge

Constraint (already documented in `docs/STATUS.md`): a live SwiftUI `Canvas` does
not render inside a `MenuBarExtra` label — AppKit snapshots the label to a
*template image* and `Canvas` draws blank. The fix already prescribed there: don't
draw live, **pre-render** a template image and swap it in.

- New pure geometry helper in `UsageMeterKit` (headless, testable), e.g.
  `GaugeGeometry.arcSweep(percent: Double) -> (start: Double, end: Double)` in
  degrees — no AppKit/CoreGraphics, just math, so it can be unit tested like the
  rest of the kit.
- New renderer in the app target, `Sources/UsageMeter/MenuBar/MenuBarGaugeRenderer.swift`:
  a small CoreGraphics function `render(percent: Double?, pointSize: CGFloat) -> NSImage`
  that draws a **ring/donut**: a low-alpha full-circle track plus a full-alpha arc
  filled proportionally to `percent` (12 o'clock start, clockwise). Because
  template images are alpha-only masks, color doesn't matter here — draw solid
  black, mark `.isTemplate = true`. When `percent == nil` (logged out / local-only,
  no session metric), draw just the empty track — same "neutral, no claim" meaning
  the current SF Symbol has today.
- `MenuBarLabel` swaps `Image(systemName: "gauge.with.dots.needle.50percent")` for
  `Image(nsImage: renderer.render(percent: session?.percent, pointSize: ...))
  .renderingMode(.template)`. The existing `.foregroundStyle(tint)` on the
  surrounding `HStack` keeps recoloring the whole glyph on the 75/90% escalation —
  no change needed there, template-image tinting works the same way SF Symbol
  tinting already does.
- Regeneration is cheap (one tiny CG draw) and piggybacks on the existing refresh
  cycle — no caching, no new timers; SwiftUI re-evaluates `MenuBarLabel.body` on
  every `model.snapshot` change already.
- Width: glyph-only sizing stays in the same ballpark as today's SF Symbol
  (~16–18pt); the optional "%" text next to it stays gated on the existing
  `showPercentInMenuBar` setting, unchanged. The ask for "always visible / more
  obvious" is satisfied by the glyph itself now visibly encoding fill level at a
  glance, not by widening the status item.

## 4. Weekly Fable limit (Source A)

Verified against a real captured response
(`~/Library/Application Support/UsageMeter/account_capture.json`, 2026-07-06):
`limits[]` contains a `weekly_scoped` entry with
`scope: { model: { id: null, display_name: "Fable" } }` alongside `percent`,
`resets_at`, `is_active` — the same shape class as the generic weekly/session
limits, just model-scoped. This is real, not guessed.

- `AccountUsageDecoder.RawUsage.Limit` gains `scope: Scope?` where
  `Scope { model: ModelScope? }` and `ModelScope { id: String?; display_name: String? }`.
- Classification order in the `limits` fallback loop changes: check
  `scope?.model?.display_name` (case-insensitive contains) **before** falling back
  to the generic `kind`/`group` text heuristics, so a Fable-scoped weekly limit
  isn't silently absorbed into the generic `weekly` bucket the way it is today
  (harmless today only because `weekly` is already filled by `seven_day` first —
  today Fable data is dropped on the floor entirely). New branch:
  `display_name` contains "fable" → `weeklyFable = weeklyFable ?? metric`.
- `AccountUsage` (`Sources/UsageMeterKit/Models/AccountUsage.swift`) gains
  `weeklyFable: UsageMetric?`, mirroring `weeklyOpus` exactly: constructor param,
  `hasAnyMetric`, `peakPercent`. `Codable` — optional, so existing cached
  `AccountUsage` blobs without the field decode as `nil`, no migration needed.
- `decodeHeuristic` (last-resort fallback for unknown shapes) gets the same
  `key.contains("fable")` branch for symmetry with its existing `opus` check —
  cheap, keeps both decode paths consistent.
- UI (`MenuBarContentView.accountMetrics`): a `compactMetric("Weekly Fable", ...)`
  row directly under "Weekly Opus", shown only when `account.weeklyFable != nil`
  (same "silently absent if the plan doesn't expose it" pattern as Opus).
- `limitBanner`'s "nearest to limit" `compactMap` array
  (`[session, weekly, weeklyOpus]`) gains `weeklyFable`.
- Menu-bar tint escalation (`MenuBarLabel.tint`) stays keyed on `session.percent`
  only — out of scope, consistent with its existing "act now" design note.

## Testing

- `GaugeGeometry` (new, UsageMeterKit): unit tests for 0%, 50%, 100%, and an
  out-of-range clamp (>100 / <0), matching the kit's existing pure-function test
  style.
- `AccountUsageDecoderTests`: new fixture derived from the real
  `account_capture.json` shape (org id replaced with a placeholder) asserting
  `weeklyFable` decodes with the right percent/reset; a negative fixture where
  `scope.model.display_name` is some other model (e.g. "Sonnet") asserting it does
  **not** land in `weeklyFable`.
- `MenuBarGaugeRenderer` (AppKit-dependent CG drawing) is not unit tested, same
  precedent as `Scripts/icon/render.swift` — verify visually via `make run` /
  `make demo` across light/dark and at the 75/90% color thresholds.
- Manual verification pass (per this repo's `verify` skill): `make demo`, check
  the popover glance has no API-value line, colors read purple in both
  appearances, the menu-bar glyph visibly fills/empties as demo data changes, and
  (if a Fable-scoped limit is present in a real logged-in session) the "Weekly
  Fable" row appears correctly.

## Unchanged

Source B token/cost math, Dashboard's detailed cost cards, `spend`/pay-as-you-go
display, notification thresholds, `AccountRefreshPolicy` cadence, login flow,
Status (Source C), `ok`/`warning`/`danger` semantic colors, cache schema version.
