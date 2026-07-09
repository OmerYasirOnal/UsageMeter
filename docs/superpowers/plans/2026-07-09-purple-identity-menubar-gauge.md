# Purple identity, menu-bar dynamic gauge, drop API value, Weekly Fable — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Recolor the app's identity from teal/terracotta ("Kiln") to a violet/plum
purple duotone (including the app icon), replace the static SF Symbol menu-bar
glyph with a template image that visually fills as usage % rises, drop the "API
value" line from the popover glance (Dashboard keeps it), and surface a "Weekly
Fable" limit row from a real field discovered in claude.ai's account usage
response.

**Architecture:** Four independent slices touching the same visual surface.
Color changes are constant-only edits to `Theme.swift` (app) and
`Scripts/icon/render.swift` (icon). The menu-bar glyph gets a new pure geometry
helper in `UsageMeterKit` (testable) plus a small CoreGraphics renderer in the
app target (not unit-tested — AppKit drawing, verified visually, same precedent
as the icon script). The Fable limit is a new optional field threaded through
`AccountUsage` + `AccountUsageDecoder`, decoded from the real `limits[].scope`
shape and surfaced as one more popover row, following the exact pattern
`weeklyOpus` already uses.

**Tech Stack:** Swift 6, SwiftUI, AppKit (`NSStatusItem`/`NSImage` template
images), CoreGraphics, Swift Testing (`@Suite`/`@Test`/`#expect`/`#require`).

## Global Constraints

- Design source of truth: `docs/superpowers/specs/2026-07-09-purple-identity-menubar-gauge-design.md` — every task below implements one section of it.
- `Theme.ok` / `Theme.warning` / `Theme.danger` (semantic escalation colors) are NOT touched — only chrome/data-ink identity colors change.
- `AppSettings.showApiValue` and its `SettingsView` toggle are KEPT (Dashboard still reads it in 6 places) — only the popover glance's two read-sites are removed.
- All `AccountUsage` changes must stay `Codable`-compatible with existing on-disk cache (new field is `Optional`, no cache version bump).
- `swift test` (144+ tests) must pass after every task; `swift build` must succeed after every task that touches app-target code.

---

### Task 1: Recolor `Theme.swift` to the violet/plum duotone

**Files:**
- Modify: `Sources/UsageMeter/App/Theme.swift:29-52,73-87`

**Interfaces:**
- Produces: no signature changes — `Theme.accent`, `Theme.accentSoft`, `Theme.data`, `Theme.dataMuted`, `Theme.chartTop`, `Theme.chartBottom`, `Theme.heat` keep their existing types (`Color` / `[Color]`), only their hex values and doc comments change. Every other file in the app consumes these by name, so no call-site changes are needed anywhere else in this task.

- [ ] **Step 1: Update the section header and duotone doc comment**

In `Sources/UsageMeter/App/Theme.swift`, replace:

```swift
// MARK: - Theme ("Kiln": teal interactive chrome + terracotta data ink)

/// Shared visual language. The identity is a duotone: everything you *click*
/// (buttons, links, tint, pickers) is deep teal; everything that *is data*
/// (chart bars, heatmap, the gauge brand mark) is fired terracotta. Chrome and
/// data never compete, and quota state escalates teal → amber → red — a ramp
/// that stays legible under deutan/protan color vision.
```

with:

```swift
// MARK: - Theme ("Kiln": violet interactive chrome + plum/fuchsia data ink)

/// Shared visual language. The identity is a duotone: everything you *click*
/// (buttons, links, tint, pickers) is violet; everything that *is data*
/// (chart bars, heatmap, the gauge brand mark) is a plum/fuchsia purple. Chrome
/// and data never compete, and quota state escalates violet → amber → red — a
/// ramp that stays legible under deutan/protan color vision.
```

- [ ] **Step 2: Recolor chrome (accent) and data-ink colors**

Replace:

```swift
    /// Interactive chrome: buttons, links, `.tint`, selection.
    static let accent = Color(light: 0x0F766E, dark: 0x2DD4BF)
    static let accentSoft = Color(light: 0xDDF0ED, dark: 0x11332F)

    /// Data ink: chart bars, heatmap, the gauge brand mark. Not for controls.
    static let data = Color(light: 0xC2410C, dark: 0xFB923C)
    /// De-emphasized companion to `data` — trend lines and context bars that
    /// must read as "same family, quieter" next to terracotta marks.
    static let dataMuted = Color(light: 0x9A6B4F, dark: 0xB08968)
```

with:

```swift
    /// Interactive chrome: buttons, links, `.tint`, selection.
    static let accent = Color(light: 0x6D28D9, dark: 0xA78BFA)
    static let accentSoft = Color(light: 0xEDE4FB, dark: 0x2C1F47)

    /// Data ink: chart bars, heatmap, the gauge brand mark. Not for controls.
    static let data = Color(light: 0x86198F, dark: 0xE879F9)
    /// De-emphasized companion to `data` — trend lines and context bars that
    /// must read as "same family, quieter" next to the data-ink marks.
    static let dataMuted = Color(light: 0xA9779A, dark: 0xC79BC0)
```

- [ ] **Step 3: Recolor the usage-history chart gradient and the heatmap ramp**

Replace:

```swift
    /// Usage-history chart bar gradient (data ink).
    static let chartTop = Color(light: 0xE58F5E, dark: 0xFDAF74)
    static let chartBottom = Color(light: 0xC2410C, dark: 0xEA7A33)
    static var chartGradient: LinearGradient {
        LinearGradient(colors: [chartTop, chartBottom], startPoint: .top, endPoint: .bottom)
    }

    /// Opaque heatmap ramp (levels 1–4). Opaque on purpose: translucent accent
    /// steps shifted with the card behind them and vanished in dark mode.
    static let heat: [Color] = [
        Color(light: 0xF6E0D2, dark: 0x3E2415),
        Color(light: 0xECB088, dark: 0x6E3D1E),
        Color(light: 0xD0784A, dark: 0xB45E2C),
        Color(light: 0xA93E0F, dark: 0xFB923C)
    ]
```

with:

```swift
    /// Usage-history chart bar gradient (data ink).
    static let chartTop = Color(light: 0xC77DD1, dark: 0xF0A8F5)
    static let chartBottom = Color(light: 0x86198F, dark: 0xC026D3)
    static var chartGradient: LinearGradient {
        LinearGradient(colors: [chartTop, chartBottom], startPoint: .top, endPoint: .bottom)
    }

    /// Opaque heatmap ramp (levels 1–4). Opaque on purpose: translucent accent
    /// steps shifted with the card behind them and vanished in dark mode.
    static let heat: [Color] = [
        Color(light: 0xF1E0F7, dark: 0x3A1F45),
        Color(light: 0xD9AEEF, dark: 0x5E2E6E),
        Color(light: 0xB166D9, dark: 0x8B3FA0),
        Color(light: 0x86198F, dark: 0xE879F9)
    ]
```

- [ ] **Step 4: Build**

Run: `swift build`
Expected: builds cleanly (no test target touches `Theme.swift` directly — this is a constants-only change).

- [ ] **Step 5: Visual check**

Run: `make demo`
Expected: menu-bar popover and Dashboard open with the new violet buttons/links and plum/fuchsia chart bars, heatmap, and usage bars, in both light and dark appearance (toggle via Settings ▸ Appearance). If any pairing reads too dark/washed, nudge that one hex value — the exact shades are a starting point, not fixed requirements (see spec's note on this).

- [ ] **Step 6: Commit**

```bash
git add Sources/UsageMeter/App/Theme.swift
git commit -m "feat: recolor Kiln identity to violet/plum purple duotone"
```

---

### Task 2: Recolor the app icon to match

**Files:**
- Modify: `Scripts/icon/render.swift:16-21,94,101,166`
- Regenerate (committed generated assets): `Resources/AppIcon.icns`, `Resources/Assets.xcassets/AppIcon.appiconset/*.png`

**Interfaces:**
- Consumes: nothing from Task 1 (separate CG color literals, no shared code path) — same purple *family* by design intent, not by shared constants.
- Produces: no signature changes — `violetTop`/`violetMid`/`violetBottom` replace `coralTop`/`coralMid`/`coralBottom` everywhere in this one file; nothing outside `render.swift` references those names (verified: `grep -rn "coralTop\|coralMid\|coralBottom"` only matches this file).

- [ ] **Step 1: Rename and recolor the icon's color trio**

In `Scripts/icon/render.swift`, replace:

```swift
// "Kiln" fired terracotta — the app's own data-ink identity (deliberately NOT
// Claude's coral #D97757; the gauge shape is the brand, the borrowed color was
// the liability). Top #F29E54 → mid #C2410C → bottom #7C2D0C.
let coralTop    = col(0.949, 0.620, 0.329)   // #F29E54 lighter top
let coralBottom = col(0.486, 0.176, 0.047)   // #7C2D0C deeper bottom
let coralMid    = col(0.761, 0.255, 0.047)   // #C2410C
```

with:

```swift
// "Kiln" violet/plum — the app's own data-ink identity (deliberately NOT
// Claude's coral #D97757; the gauge shape is the brand, not the color). Matches
// Theme.data in the app. Top #E8A6F0 → mid #A855F7 → bottom #6B21A8.
let violetTop    = col(0.910, 0.651, 0.941)   // #E8A6F0 lighter top
let violetBottom = col(0.420, 0.129, 0.659)   // #6B21A8 deeper bottom
let violetMid    = col(0.659, 0.333, 0.969)   // #A855F7
```

- [ ] **Step 2: Update the three usage sites**

Replace (line ~94):

```swift
        ctx.setFillColor(coralBottom)
```

with:

```swift
        ctx.setFillColor(violetBottom)
```

Replace (line ~101):

```swift
        let grad = CGGradient(colorsSpace: cs, colors: [coralTop, coralBottom] as CFArray, locations: [0, 1])!
```

with:

```swift
        let grad = CGGradient(colorsSpace: cs, colors: [violetTop, violetBottom] as CFArray, locations: [0, 1])!
```

Replace (line ~166):

```swift
        if px > 32 { dot(ctx, gc, W * 0.020, coralMid) }   // pivot center
```

with:

```swift
        if px > 32 { dot(ctx, gc, W * 0.020, violetMid) }   // pivot center
```

- [ ] **Step 3: Verify no remaining references to the old names**

Run: `grep -rn "coralTop\|coralMid\|coralBottom" Scripts/icon/render.swift`
Expected: no output (all three renamed).

- [ ] **Step 4: Regenerate the icon**

Run: `make icon`
Expected: `Resources/AppIcon.icns` and `Resources/Assets.xcassets/AppIcon.appiconset/*.png` are rewritten with the new violet/plum gaugefill icon (script prints per-size render progress and exits 0).

- [ ] **Step 5: Visual check**

Open `Resources/AppIcon.icns` in Finder (Quick Look) or run `make app` and check the Dock/Finder icon — the icon should read as violet/plum instead of terracotta, at both large and small sizes.

- [ ] **Step 6: Commit**

```bash
git add Scripts/icon/render.swift Resources/AppIcon.icns Resources/Assets.xcassets/AppIcon.appiconset
git commit -m "feat: recolor app icon to match the violet/plum identity"
```

---

### Task 3: Remove "API value" from the popover glance

**Files:**
- Modify: `Sources/UsageMeter/MenuBar/MenuBarContentView.swift` (the `claudeCodeSection` computed property, currently around lines 287-312)

**Interfaces:**
- Consumes: `model.settings.showApiValue` still exists (kept for Dashboard, see Global Constraints) but this file stops reading it.
- Produces: no new symbols; `claudeCodeSection` keeps its existing `some View` return type.

- [ ] **Step 1: Simplify `claudeCodeSection`**

In `Sources/UsageMeter/MenuBar/MenuBarContentView.swift`, replace:

```swift
    private var claudeCodeSection: some View {
        let cc = model.snapshot.claudeCode
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                SectionLabel(text: "Claude Code — Today")
                Spacer()
                #if APPSTORE
                statusIncidentRow
                #endif
            }
            HStack {
                metric(title: "Tokens", value: Formatting.tokens(cc.today.totalTokens))
                Spacer()
                if model.settings.showApiValue {
                    metric(title: "API value", value: Formatting.cost(cc.todayEstimatedCost),
                           help: "What your tokens would cost at pay-as-you-go API rates — not money you're billed.")
                }
            }
            if cc.recordCount == 0 {
                emptyState
            } else {
                Text("\(cc.sessionCount) sessions · all-time ≈ \(model.settings.showApiValue ? Formatting.cost(cc.totalEstimatedCost) : Formatting.tokens(cc.total.totalTokens))")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
    }
```

with:

```swift
    private var claudeCodeSection: some View {
        let cc = model.snapshot.claudeCode
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                SectionLabel(text: "Claude Code — Today")
                Spacer()
                #if APPSTORE
                statusIncidentRow
                #endif
            }
            metric(title: "Tokens", value: Formatting.tokens(cc.today.totalTokens))
            if cc.recordCount == 0 {
                emptyState
            } else {
                Text("\(cc.sessionCount) sessions · all-time ≈ \(Formatting.tokens(cc.total.totalTokens))")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
    }
```

(The `HStack { metric(...); Spacer(); ... }` wrapper is dropped along with it since there's now only one metric on that row — `metric(title:value:)` itself is unchanged and still used elsewhere in this file, e.g. in `blockSection`.)

- [ ] **Step 2: Build**

Run: `swift build`
Expected: builds cleanly. `Formatting.cost` and `cc.todayEstimatedCost`/`cc.totalEstimatedCost` remain used by `DashboardView.swift` (unchanged), so no dead-code warnings there.

- [ ] **Step 3: Visual check**

Run: `make demo`, click the menu-bar gauge to open the popover.
Expected: "Claude Code — Today" section shows only "Tokens" (no "API value" next to it), and the caption reads "N sessions · all-time ≈ <tokens>" instead of a dollar amount.

- [ ] **Step 4: Commit**

```bash
git add Sources/UsageMeter/MenuBar/MenuBarContentView.swift
git commit -m "fix: drop API value from the popover glance (Dashboard keeps it)"
```

---

### Task 4: `GaugeGeometry` — pure fill-fraction math (TDD)

**Files:**
- Create: `Sources/UsageMeterKit/Models/GaugeGeometry.swift`
- Test: `Tests/UsageMeterKitTests/GaugeGeometryTests.swift`

**Interfaces:**
- Produces: `public enum GaugeGeometry { public static func fillFraction(percent: Double) -> Double }` — Task 5's renderer calls this.

- [ ] **Step 1: Write the failing test**

Create `Tests/UsageMeterKitTests/GaugeGeometryTests.swift`:

```swift
import Testing
@testable import UsageMeterKit

@Suite struct GaugeGeometryTests {
    @Test func zeroPercentHasNoFill() {
        #expect(GaugeGeometry.fillFraction(percent: 0) == 0)
    }

    @Test func fiftyPercentIsHalfFilled() {
        #expect(GaugeGeometry.fillFraction(percent: 50) == 0.5)
    }

    @Test func hundredPercentIsFullyFilled() {
        #expect(GaugeGeometry.fillFraction(percent: 100) == 1.0)
    }

    @Test func clampsBelowZero() {
        #expect(GaugeGeometry.fillFraction(percent: -20) == 0)
    }

    @Test func clampsAboveHundred() {
        #expect(GaugeGeometry.fillFraction(percent: 150) == 1.0)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter GaugeGeometryTests`
Expected: FAIL — `GaugeGeometry` is not defined.

- [ ] **Step 3: Write the implementation**

Create `Sources/UsageMeterKit/Models/GaugeGeometry.swift`:

```swift
import Foundation

/// Pure percent → fill-fraction math for the menu-bar gauge glyph. Kept
/// AppKit-free so it's testable like the rest of UsageMeterKit; the actual
/// CoreGraphics drawing lives in the app target's `MenuBarGaugeRenderer`.
public enum GaugeGeometry {
    /// Clamps `percent` to 0...100 and returns the fraction (0...1) of the ring
    /// that should be filled.
    public static func fillFraction(percent: Double) -> Double {
        min(100, max(0, percent)) / 100.0
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter GaugeGeometryTests`
Expected: PASS (5 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/UsageMeterKit/Models/GaugeGeometry.swift Tests/UsageMeterKitTests/GaugeGeometryTests.swift
git commit -m "feat(kit): add GaugeGeometry pure fill-fraction math"
```

---

### Task 5: `MenuBarGaugeRenderer` — template-image gauge drawing

**Files:**
- Create: `Sources/UsageMeter/MenuBar/MenuBarGaugeRenderer.swift`

**Interfaces:**
- Consumes: `GaugeGeometry.fillFraction(percent:) -> Double` (Task 4).
- Produces: `enum MenuBarGaugeRenderer { static func render(percent: Double?, pointSize: CGFloat = 16) -> NSImage }` — Task 6 calls this.

Not unit-tested (AppKit/CoreGraphics drawing — same precedent as `Scripts/icon/render.swift`, which also has no automated test). Verified visually in Step 3.

- [ ] **Step 1: Write the renderer**

Create `Sources/UsageMeter/MenuBar/MenuBarGaugeRenderer.swift`:

```swift
import AppKit
import UsageMeterKit

/// Renders the menu-bar gauge as a template image: a low-alpha ring track plus
/// a full-alpha arc filled to `percent`, starting at 12 o'clock and sweeping
/// clockwise. Template images are alpha-only masks — AppKit/SwiftUI recolor
/// them via `.foregroundStyle`, the same mechanism that tinted the SF Symbol
/// glyph this replaces (see `MenuBarLabel.tint`).
///
/// A live SwiftUI `Canvas` does NOT render inside a `MenuBarExtra` label —
/// AppKit snapshots the label to a template image and `Canvas` draws blank
/// (documented in docs/STATUS.md). That's why this is pre-rendered to an
/// `NSImage` instead of drawn live.
enum MenuBarGaugeRenderer {
    /// `percent == nil` (logged out / local-only, no session metric) draws just
    /// the empty track — the same "neutral, no claim" meaning the old SF Symbol
    /// glyph had with no live account data.
    static func render(percent: Double?, pointSize: CGFloat = 16) -> NSImage {
        let scale: CGFloat = 2
        let px = Int(pointSize * scale)
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        rep.size = NSSize(width: pointSize, height: pointSize)

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        if let ctx = NSGraphicsContext.current?.cgContext {
            draw(in: ctx, px: CGFloat(px), percent: percent)
        }
        NSGraphicsContext.restoreGraphicsState()

        let image = NSImage(size: rep.size)
        image.addRepresentation(rep)
        image.isTemplate = true
        return image
    }

    private static func draw(in ctx: CGContext, px: CGFloat, percent: Double?) {
        let center = CGPoint(x: px / 2, y: px / 2)
        let radius = px * 0.36
        ctx.setLineWidth(px * 0.14)
        ctx.setLineCap(.round)

        // Full track, low alpha.
        ctx.setStrokeColor(CGColor(gray: 0, alpha: 0.28))
        ctx.addArc(center: center, radius: radius, startAngle: 0, endAngle: .pi * 2, clockwise: false)
        ctx.strokePath()

        guard let percent else { return }
        let fraction = GaugeGeometry.fillFraction(percent: percent)
        guard fraction > 0 else { return }

        // Filled arc, full alpha, starting at 12 o'clock, sweeping clockwise.
        let start = -CGFloat.pi / 2
        let end = start + CGFloat(fraction) * 2 * .pi
        ctx.setStrokeColor(CGColor(gray: 0, alpha: 1))
        ctx.addArc(center: center, radius: radius, startAngle: start, endAngle: end, clockwise: false)
        ctx.strokePath()
    }
}
```

- [ ] **Step 2: Build**

Run: `swift build`
Expected: builds cleanly. `MenuBarGaugeRenderer` has no automated test (AppKit/CoreGraphics drawing, same precedent as `Scripts/icon/render.swift`) and isn't called from anywhere yet — Task 6 wires it in and is where the drawing gets its actual visual check via `make demo`.

- [ ] **Step 3: Commit**

```bash
git add Sources/UsageMeter/MenuBar/MenuBarGaugeRenderer.swift
git commit -m "feat: add MenuBarGaugeRenderer (template-image filling gauge)"
```

---

### Task 6: Wire the dynamic gauge into `MenuBarLabel`

**Files:**
- Modify: `Sources/UsageMeter/MenuBar/MenuBarLabel.swift`

**Interfaces:**
- Consumes: `MenuBarGaugeRenderer.render(percent: Double?, pointSize: CGFloat) -> NSImage` (Task 5).

- [ ] **Step 1: Swap the SF Symbol for the rendered gauge**

In `Sources/UsageMeter/MenuBar/MenuBarLabel.swift`, replace:

```swift
            Image(systemName: "gauge.with.dots.needle.50percent")
```

with:

```swift
            Image(nsImage: MenuBarGaugeRenderer.render(percent: model.snapshot.account?.session?.percent))
                .renderingMode(.template)
```

Also update the file's header doc comment, which currently says the menu bar
"uses the SF Symbol gauge" and explains why — replace:

```swift
/// Note: the menu-bar label is rendered by AppKit as a *template image*, which
/// only reliably reproduces `Text`/SF-Symbol `Image` — custom `Canvas` drawing
/// (our `GaugeGlyph`) silently drops out and breaks the layout, so the menu bar
/// uses the SF Symbol gauge (same family as the app icon). `GaugeGlyph` is used
/// where it renders correctly: the app icon and the popover header (a real window).
```

with:

```swift
/// Note: the menu-bar label is rendered by AppKit as a *template image*, which
/// only reliably reproduces `Text`/SF-Symbol `Image` — a live `Canvas` silently
/// drops out and breaks the layout. `MenuBarGaugeRenderer` sidesteps this by
/// pre-rendering the gauge to an `NSImage` (a real filling ring, not a static
/// glyph) instead of drawing it live.
```

- [ ] **Step 2: Build**

Run: `swift build`
Expected: builds cleanly.

- [ ] **Step 3: Visual check**

Run: `make demo`.
Expected: the menu-bar item shows a ring that's about 42% filled (demo session
percent), tinted `.primary` (below the 75% warning threshold). Toggle Settings ▸
"Show sample data" off/on or quit and relaunch without `USAGEMETER_DEMO` to
confirm the logged-out state shows an empty (untinted) ring, not a crash or
blank glyph.

- [ ] **Step 4: Commit**

```bash
git add Sources/UsageMeter/MenuBar/MenuBarLabel.swift
git commit -m "feat: menu-bar glyph is now a live filling gauge, not a static SF Symbol"
```

---

### Task 7: Decode the real "Weekly Fable" limit (TDD)

**Files:**
- Modify: `Sources/UsageMeterKit/Models/AccountUsage.swift`
- Modify: `Sources/UsageMeterKit/Account/AccountUsageDecoder.swift`
- Test: `Tests/UsageMeterKitTests/AccountTests.swift`

**Interfaces:**
- Produces: `AccountUsage.weeklyFable: UsageMetric?` (mirrors `weeklyOpus` exactly: constructor param, included in `hasAnyMetric` and `peakPercent`). `AccountUsageDecoder.decode(_:now:)` populates it from a real `limits[]` entry whose `scope.model.display_name` (or `id`) contains "fable" — verified against the real captured claude.ai response at `~/Library/Application Support/UsageMeter/account_capture.json` (2026-07-06).

- [ ] **Step 1: Write the failing tests**

In `Tests/UsageMeterKitTests/AccountTests.swift`, add inside `@Suite struct AccountUsageDecoderTests { ... }` (after `decodesRealSpendMinorUnits`, before the closing `}`):

```swift
    /// Derived from the real captured claude.ai /usage response (2026-07-06,
    /// account_capture.json) — org id redacted, unrelated null fields trimmed,
    /// Fable's percent bumped from 0 to 15 so the assertion is meaningful.
    @Test func decodesWeeklyFableFromScopedLimit() throws {
        let json = #"""
        {
          "five_hour": {"utilization": 2, "resets_at": "2026-07-06T14:00:00Z"},
          "seven_day": {"utilization": 0, "resets_at": "2026-07-08T08:00:00Z"},
          "seven_day_opus": null,
          "limits": [
            {"kind": "session", "group": "session", "percent": 2, "resets_at": "2026-07-06T14:00:00Z", "scope": null, "is_active": true},
            {"kind": "weekly_all", "group": "weekly", "percent": 0, "resets_at": "2026-07-08T08:00:00Z", "scope": null, "is_active": false},
            {"kind": "weekly_scoped", "group": "weekly", "percent": 15, "resets_at": "2026-07-08T08:00:00Z", "scope": {"model": {"id": null, "display_name": "Fable"}}, "is_active": false}
          ]
        }
        """#
        let u = try #require(AccountUsageDecoder.decode(Data(json.utf8), now: fixedNow))
        #expect(u.weeklyFable?.displayPercent == 15)
        #expect(u.weeklyFable?.resetsAt == TestTime.date("2026-07-08T08:00:00Z"))
        #expect(u.weekly?.displayPercent == 0) // weekly_all, unaffected by the Fable-scoped limit
    }

    @Test func doesNotMisclassifyOtherModelScopedLimitsAsFable() throws {
        let json = #"""
        {
          "five_hour": {"utilization": 5, "resets_at": "2026-07-06T14:00:00Z"},
          "limits": [
            {"kind": "weekly_scoped", "group": "weekly", "percent": 40, "resets_at": "2026-07-08T08:00:00Z", "scope": {"model": {"id": null, "display_name": "Sonnet"}}, "is_active": true}
          ]
        }
        """#
        let u = try #require(AccountUsageDecoder.decode(Data(json.utf8), now: fixedNow))
        #expect(u.weeklyFable == nil)
    }
```

In the same file, inside `@Suite struct AccountModelTests { ... }`, replace the existing `peakAndHasAnyMetric` test:

```swift
    @Test func peakAndHasAnyMetric() {
        #expect(AccountUsage().hasAnyMetric == false)
        let u = AccountUsage(session: UsageMetric(percent: 12),
                             weekly: UsageMetric(percent: 80),
                             weeklyOpus: UsageMetric(percent: 55))
        #expect(u.hasAnyMetric)
        #expect(u.peakPercent == 80)
    }
```

with:

```swift
    @Test func peakAndHasAnyMetric() {
        #expect(AccountUsage().hasAnyMetric == false)
        let u = AccountUsage(session: UsageMetric(percent: 12),
                             weekly: UsageMetric(percent: 80),
                             weeklyOpus: UsageMetric(percent: 55),
                             weeklyFable: UsageMetric(percent: 95))
        #expect(u.hasAnyMetric)
        #expect(u.peakPercent == 95)
    }
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --filter AccountUsageDecoderTests`
Expected: FAIL — `weeklyFable` is not a member of `AccountUsage`, and `Limit` has no `scope`.

- [ ] **Step 3: Add `weeklyFable` to the model**

In `Sources/UsageMeterKit/Models/AccountUsage.swift`, replace:

```swift
public struct AccountUsage: Codable, Sendable, Equatable {
    public var session: UsageMetric?
    public var weekly: UsageMetric?
    /// Separate weekly Opus limit, when the account/plan reports one.
    public var weeklyOpus: UsageMetric?
    /// Real pay-as-you-go spend from claude.ai (the user's actual money).
    public var spend: SpendInfo?
    /// When these numbers were fetched.
    public var fetchedAt: Date?

    public init(
        session: UsageMetric? = nil,
        weekly: UsageMetric? = nil,
        weeklyOpus: UsageMetric? = nil,
        spend: SpendInfo? = nil,
        fetchedAt: Date? = nil
    ) {
        self.session = session
        self.weekly = weekly
        self.weeklyOpus = weeklyOpus
        self.spend = spend
        self.fetchedAt = fetchedAt
    }

    /// Whether any dimension was actually populated.
    public var hasAnyMetric: Bool {
        session != nil || weekly != nil || weeklyOpus != nil
    }

    /// The highest utilization across dimensions — drives "near limit" logic.
    public var peakPercent: Double {
        [session?.percent, weekly?.percent, weeklyOpus?.percent]
            .compactMap { $0 }
            .max() ?? 0
    }
}
```

with:

```swift
public struct AccountUsage: Codable, Sendable, Equatable {
    public var session: UsageMetric?
    public var weekly: UsageMetric?
    /// Separate weekly Opus limit, when the account/plan reports one.
    public var weeklyOpus: UsageMetric?
    /// Separate weekly Fable limit, when the account/plan reports one (a
    /// model-scoped entry in the `limits[]` array, not a top-level window).
    public var weeklyFable: UsageMetric?
    /// Real pay-as-you-go spend from claude.ai (the user's actual money).
    public var spend: SpendInfo?
    /// When these numbers were fetched.
    public var fetchedAt: Date?

    public init(
        session: UsageMetric? = nil,
        weekly: UsageMetric? = nil,
        weeklyOpus: UsageMetric? = nil,
        weeklyFable: UsageMetric? = nil,
        spend: SpendInfo? = nil,
        fetchedAt: Date? = nil
    ) {
        self.session = session
        self.weekly = weekly
        self.weeklyOpus = weeklyOpus
        self.weeklyFable = weeklyFable
        self.spend = spend
        self.fetchedAt = fetchedAt
    }

    /// Whether any dimension was actually populated.
    public var hasAnyMetric: Bool {
        session != nil || weekly != nil || weeklyOpus != nil || weeklyFable != nil
    }

    /// The highest utilization across dimensions — drives "near limit" logic.
    public var peakPercent: Double {
        [session?.percent, weekly?.percent, weeklyOpus?.percent, weeklyFable?.percent]
            .compactMap { $0 }
            .max() ?? 0
    }
}
```

- [ ] **Step 4: Decode it in `AccountUsageDecoder`**

In `Sources/UsageMeterKit/Account/AccountUsageDecoder.swift`, replace the `Limit` struct:

```swift
        struct Limit: Decodable {
            let kind: String?; let group: String?; let percent: Double?
            let resets_at: String?; let is_active: Bool?
        }
```

with:

```swift
        struct Limit: Decodable {
            struct Scope: Decodable {
                struct Model: Decodable { let id: String?; let display_name: String? }
                let model: Model?
            }
            let kind: String?; let group: String?; let percent: Double?
            let resets_at: String?; let is_active: Bool?
            let scope: Scope?
        }
```

Replace the classification block:

```swift
        var session = windowMetric(raw.five_hour)
        var weekly = windowMetric(raw.seven_day)
        var weeklyOpus = windowMetric(raw.seven_day_opus)

        // FALLBACK: the `limits` array (also 0...100) for any category the windows
        // didn't provide. Classify by kind+group tokens.
        for limit in raw.limits ?? [] {
            guard let p = limit.percent else { continue }
            let key = ((limit.kind ?? "") + " " + (limit.group ?? "")).lowercased()
            let metric = UsageMetric(percent: min(100.0, max(0.0, p)), resetsAt: reset(limit.resets_at))
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
```

with:

```swift
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
```

Replace the `AccountUsage(...)` construction just below it:

```swift
        let usage = AccountUsage(session: session, weekly: weekly, weeklyOpus: weeklyOpus,
                                 spend: spend, fetchedAt: now)
```

with:

```swift
        let usage = AccountUsage(session: session, weekly: weekly, weeklyOpus: weeklyOpus,
                                 weeklyFable: weeklyFable, spend: spend, fetchedAt: now)
```

- [ ] **Step 5: Extend the heuristic fallback for symmetry**

In the same file, replace:

```swift
    static func decodeHeuristic(_ data: Data, now: Date) -> AccountUsage? {
        guard data.count <= 1_000_000,
              let root = try? JSONSerialization.jsonObject(with: data) else { return nil }

        var session: UsageMetric?
        var weekly: UsageMetric?
        var weeklyOpus: UsageMetric?

        walk(root, nearestKey: "", depth: 0) { dict, nearestKey in
            guard let metric = metric(from: dict, now: now) else { return }
            let key = nearestKey.lowercased()
            if key.contains("opus") {
                weeklyOpus = weeklyOpus ?? metric
            } else if key.contains("week") || key.contains("seven")
                        || key.contains("7day") || key.contains("7_day") {
                weekly = weekly ?? metric
            } else if key.contains("session") || key.contains("five")
                        || key.contains("hour") || key.contains("5h") || key.contains("5_hour") {
                session = session ?? metric
            }
        }

        guard session != nil || weekly != nil || weeklyOpus != nil else { return nil }
        return AccountUsage(session: session, weekly: weekly, weeklyOpus: weeklyOpus, fetchedAt: now)
    }
```

with:

```swift
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
```

- [ ] **Step 6: Run tests to verify they pass**

Run: `swift test --filter AccountUsageDecoderTests && swift test --filter AccountModelTests`
Expected: PASS, including the two new tests and the updated `peakAndHasAnyMetric`.

- [ ] **Step 7: Run the full suite**

Run: `swift test`
Expected: all tests pass (no other test references the old `Limit` shape or the 3-arg-minus-fable `AccountUsage` positions since Swift's memberwise/keyword init calls are unaffected by adding a new optional parameter after existing ones).

- [ ] **Step 8: Commit**

```bash
git add Sources/UsageMeterKit/Models/AccountUsage.swift Sources/UsageMeterKit/Account/AccountUsageDecoder.swift Tests/UsageMeterKitTests/AccountTests.swift
git commit -m "feat(kit): decode Weekly Fable limit from claude.ai's scoped limits[]"
```

---

### Task 8: Surface "Weekly Fable" in the popover

**Files:**
- Modify: `Sources/UsageMeter/MenuBar/MenuBarContentView.swift`
- Modify: `Sources/UsageMeter/App/DemoData.swift`

**Interfaces:**
- Consumes: `AccountUsage.weeklyFable: UsageMetric?` (Task 7).

- [ ] **Step 1: Add the popover row**

In `Sources/UsageMeter/MenuBar/MenuBarContentView.swift`, inside `accountMetrics(_:)`, replace:

```swift
            if let weekly = account.weekly { compactMetric("Weekly Limit", key: "Weekly", weekly) }
            if let opus = account.weeklyOpus { compactMetric("Weekly Opus", key: "Weekly Opus", opus) }
```

with:

```swift
            if let weekly = account.weekly { compactMetric("Weekly Limit", key: "Weekly", weekly) }
            if let opus = account.weeklyOpus { compactMetric("Weekly Opus", key: "Weekly Opus", opus) }
            if let fable = account.weeklyFable { compactMetric("Weekly Fable", key: "Weekly Fable", fable) }
```

- [ ] **Step 2: Include it in the near-limit banner**

In the same file, inside `limitBanner(_:)`, replace:

```swift
            let nearest = [account.session, account.weekly, account.weeklyOpus]
                .compactMap { $0 }
                .max(by: { $0.percent < $1.percent })
```

with:

```swift
            let nearest = [account.session, account.weekly, account.weeklyOpus, account.weeklyFable]
                .compactMap { $0 }
                .max(by: { $0.percent < $1.percent })
```

- [ ] **Step 3: Add it to demo data so it's visible without a real Fable-enabled account**

In `Sources/UsageMeter/App/DemoData.swift`, replace:

```swift
        return AccountUsage(
            session: UsageMetric(percent: 42, resetsAt: now.addingTimeInterval(2 * 3600 + 9 * 60)),
            weekly: UsageMetric(percent: 18, resetsAt: now.addingTimeInterval(3 * 86_400 + 4 * 3600)),
            weeklyOpus: UsageMetric(percent: 31, resetsAt: now.addingTimeInterval(3 * 86_400 + 4 * 3600)),
            spend: SpendInfo(usedMinor: 0, currency: "USD", exponent: 2, canPurchaseCredits: true),
            fetchedAt: now)
```

with:

```swift
        return AccountUsage(
            session: UsageMetric(percent: 42, resetsAt: now.addingTimeInterval(2 * 3600 + 9 * 60)),
            weekly: UsageMetric(percent: 18, resetsAt: now.addingTimeInterval(3 * 86_400 + 4 * 3600)),
            weeklyOpus: UsageMetric(percent: 31, resetsAt: now.addingTimeInterval(3 * 86_400 + 4 * 3600)),
            weeklyFable: UsageMetric(percent: 6, resetsAt: now.addingTimeInterval(3 * 86_400 + 4 * 3600)),
            spend: SpendInfo(usedMinor: 0, currency: "USD", exponent: 2, canPurchaseCredits: true),
            fetchedAt: now)
```

- [ ] **Step 4: Build**

Run: `swift build`
Expected: builds cleanly.

- [ ] **Step 5: Visual check**

Run: `make demo`, open the popover.
Expected: a "Weekly Fable" row appears directly under "Weekly Opus", showing 6%
with the correct reset countdown.

- [ ] **Step 6: Commit**

```bash
git add Sources/UsageMeter/MenuBar/MenuBarContentView.swift Sources/UsageMeter/App/DemoData.swift
git commit -m "feat: show Weekly Fable in the popover"
```

---

### Task 9: Full verification pass

**Files:** none (verification only).

- [ ] **Step 1: Run the full test suite**

Run: `swift test`
Expected: all tests pass (144 pre-existing + 7 new: 5 `GaugeGeometryTests` + 2 `AccountUsageDecoderTests`, plus the modified `peakAndHasAnyMetric`).

- [ ] **Step 2: Build both app configurations**

Run: `swift build`
Expected: succeeds (default, full A+B+C GitHub build).

Run: `swift build -Xswiftc -DAPPSTORE`
Expected: succeeds (local-only build — confirms `MenuBarGaugeRenderer`/`MenuBarLabel` changes don't depend on anything compiled out under `#if APPSTORE`, since `model.snapshot.account` is simply `nil` there and the renderer already handles `percent == nil`).

- [ ] **Step 3: End-to-end manual check**

Run: `make demo`. Confirm, in one pass:
- Menu-bar glyph is a filling ring (not the old SF Symbol), ~42% full, tinted `.primary`.
- Popover: violet buttons/links, no "API value" line, "Weekly Fable" row present at 6%.
- Open Dashboard (⌘D from the popover): confirm its cost/API-value cards are still present and unchanged, chart bars and heatmap read plum/fuchsia.
- Toggle Settings ▸ Appearance between Light/Dark: colors stay legible and distinguishable (chrome vs. data) in both.

- [ ] **Step 4: Update `docs/STATUS.md`**

Add a line under the TODO/recent-changes section noting: the menu-bar glyph is
now a rendered dynamic gauge (not the SF Symbol) via `MenuBarGaugeRenderer`;
identity recolored violet/plum (was Kiln teal/terracotta); "Weekly Fable" now
decodes from `limits[].scope.model.display_name`; and the open follow-up that
README/App Store screenshots still show the old Kiln colors and should be
recaptured next.

- [ ] **Step 5: Commit**

```bash
git add docs/STATUS.md
git commit -m "docs(STATUS): purple identity + dynamic menu-bar gauge + Weekly Fable shipped"
```
