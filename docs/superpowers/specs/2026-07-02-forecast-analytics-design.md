# Forecast analytics + durable login — design

**Date:** 2026-07-02. User request: richer, animated, *meaningful* charts with
data-science-grounded predictions ("at this pace you'll finish X in Y"), and a
login that stays remembered for a long time.

## What already exists (don't rebuild)

`UsageProjection` (Kit) already answers "when do you hit the session/weekly
limit at your smoothed pace" and is shown on the dashboard account cards and in
the popover (on `.exhausts`). This batch ADDS the missing layers.

## 1. Day-end forecast (`DayEndForecast`, Kit)

"On pace for ~420M tokens / ~$560 today."

- **Intraday profile:** while aggregating stats, compute from the records of the
  last 14 *complete* local days (excluding today, days with ≥1M tokens only) the
  average cumulative fraction of a day's tokens reached by each local hour
  (`cumFraction[hour 0…24]`, monotonic). Stored on `ClaudeCodeStats` as
  `intradayProfile: [Double]?` (25 entries) — tiny, Codable.
- **Forecast:** `projected = tokensToday / max(cumFraction(now), 0.05)`; the
  0.05 floor stops silly extrapolation just after midnight. Band: recompute with
  the per-day fraction dispersion (±1 population std of the day fractions at the
  current hour, clamped to [0.02, 1]) → `low…high` range. Projected cost = blended
  `todayCost/todayTokens × projected`.
- **Honesty gates:** needs ≥3 profile days, `tokensToday > 0`, and local time
  ≥ 08:00 OR cumFraction(now) ≥ 0.15 — otherwise `nil` (UI shows nothing rather
  than a wild guess). Pure `DayEndForecast.compute(...)`, fully unit-tested.

## 2. Dashboard chart upgrades (Kiln rules apply; read the dataviz skill first)

- **History chart:** 7-day moving-average `LineMark` overlay (secondary data ink,
  `Theme.accent` NOT used — data stays terracotta family; MA uses a desaturated
  brown/neutral) on 30D/90D/All ranges. Today's bar (7D/30D) gains a translucent
  stacked "projected remainder" segment up to the forecast midpoint with a dashed
  `RuleMark` cap; legend-free, explained by the forecast card.
- **Forecast card** in the insights row (replaces nothing; row wraps): "On pace
  for ~X tokens today" + "≈ $Y · range X₁–X₂" caption. Hidden when forecast is nil.
- **Weekday profile card:** avg tokens per weekday (last 12 weeks, computed
  UI-side from existing daily points), `BarMark`, today's weekday emphasized in
  `Theme.data`, others in the muted ramp — answers "which days do I actually work".
- **Animation:** bars grow in on first appear (scale from zero via `appeared`
  state; already partially present), MA line draws with `.easeOut`; ALL gated on
  `accessibilityReduceMotion`.

## 3. Durable login (Set-Cookie write-back)

Root cause found in code review: `LiveAccountUsageClient` replays with a manual
`Cookie` header via `URLSession.shared`; claude.ai's refreshed/rotated session
cookies in `Set-Cookie` responses are never written back to the isolated
`WKWebsiteDataStore`, so the stored session dies at its original expiry even
though the server kept extending it.

- Kit: `LiveAccountUsageClient` gains `onSetCookies: (@Sendable ([HTTPCookie]) -> Void)?`;
  after ANY response that carries them (2xx incl. redirects), extract via
  `HTTPCookie.cookies(withResponseHeaderFields:for:)` (host-scoped) and call it.
  Unit-tested with the existing mock-URLProtocol harness.
- App: `AccountAuth.storeCookies(_:)` writes them into
  `dataStore.httpCookieStore` (main-actor). AppModel wires the callback.
- Effect: as long as the app refreshes periodically (it does, adaptively), the
  session self-renews like a real browser. Honest caveat: a server-side absolute
  session expiry can still log us out — nothing client-side fixes that.

## Error handling

- Forecast: any missing input → nil → UI omits the card and the projected bar
  segment. Profile never divides by zero (floor).
- Cookie write-back: never throws; invalid/foreign-host cookies are filtered by
  the RFC-6265-ish suffix match already used for sending.

## Testing

- `DayEndForecastTests`: profile math (monotonic, weighting), floor, gates,
  band, blended cost; fixture records for the profile aggregation.
- `LiveAccountUsageClientTests`: add Set-Cookie → callback case + host filter.
- Both build variants; 154 existing tests stay green.

## Out of scope (deferred)

Hour-of-day heat strip, per-project forecasts, popover forecast copy changes
(the popover already shows `.exhausts` projections), GRDB.
