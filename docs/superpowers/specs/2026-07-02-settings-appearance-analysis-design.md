# Settings rebuild + app-wide appearance + chart analysis — design

**Date:** 2026-07-02. User asks: (1) rebuild the Settings panel properly with a
proper lifecycle, (2) make dark/light/system work correctly EVERYWHERE (incl.
the known popover-window quirk), (3) make charts better with more analysis.
Afterwards: recapture README screenshots and cut notarized v0.2.2.

## 1. App-wide appearance (fixes the popover quirk at the root)

Today the theme override is applied per-view (`preferredColorScheme` in
popover/dashboard/settings), so window chrome, popover material, and menus stay
on the system appearance — the documented quirk. Fix:

- `AppAppearance.nsAppearance: NSAppearance?` (`nil` for `.system`,
  `.aqua`/`.darkAqua` otherwise).
- `AppModel` applies `NSApp.appearance = settings.appearance.nsAppearance` at
  init and whenever the setting changes (the single source of truth).
- Remove all three `preferredColorScheme` modifiers — `Color(light:dark:)`
  dynamic providers then resolve against the window appearance everywhere,
  including the MenuBarExtra window.

## 2. Settings rebuild (tabbed, standard macOS settings anatomy)

`SettingsView` becomes a `TabView` in the existing `Settings` scene (⌘, keeps
working; `managesActivationPolicy()` stays on the root; the gear button's
`showSettingsWindow:` path unchanged):

- **General** — appearance picker, menu-bar content toggles (% / today's API
  value), "API value" estimate toggle + caption, launch at login, sample data.
- **Data** — Claude Code log folders editor (+ sandbox grant-access row),
  refresh interval stepper. Keeps the commit-on-focus-loss lifecycle for the
  folders text editor (rootsText state moves into this tab).
- **Notifications** — master toggle, explanation, daily budget field.
- **Account** (`#if !APPSTORE`) — sign-in state, Log in / Log out, ToS note.
- **About** — app version/build (from Bundle), privacy statements, trademark
  line.

Each tab is its own `Form` with `.formStyle(.grouped)`, fixed width 560; height
hugs content per tab (standard settings behavior). No behavior changes to the
underlying settings model.

## 3. Charts: hover + analysis

- **Hover tooltip** on the Usage History chart: `.chartOverlay` +
  `onContinuousHover` → nearest day; vertical `RuleMark` + annotation card
  (day, tokens, cost). Hit target = full plot height (dataviz interaction rule).
- **Week-over-week card**: Kit gains
  `DashboardMetrics.weekOverWeekChange(_ points:, now:, calendar:) -> Double?`
  (last 7 complete days vs the 7 before; nil when the earlier window is empty).
  New insight card: "↑ 34% vs previous 7 days" (arrow via SF Symbol, neutral
  tint — informational, not alarming).
- **Heatmap month labels**: `ActivityGrid` gets a top row of month abbreviations
  aligned to the column where each month starts (GitHub-style).

## Testing

Kit: `weekOverWeekChange` unit tests (basic, empty-previous → nil, zero
handling). UI/appearance: build both variants; visual pass light/dark/system
on popover + dashboard + settings when the user is idle (or user-confirmed).

## Out of scope

Heatmap quantile levels, dashboard range/toolbar migration, right-click status
menu (still deferred).
