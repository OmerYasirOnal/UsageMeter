# Forecast Analytics + Durable Login Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Day-end usage forecast ("on pace for ~X tokens / $Y today") grounded in a 14-day intraday profile, richer/animated dashboard charts (7-day MA overlay, projected-remainder bar, weekday profile card), and a login session that self-renews via Set-Cookie write-back.

**Architecture:** Pure `DayEndForecast` + `IntradayProfile` in Kit, profile computed inside `DailyAggregator.aggregate` (records are in hand there) and carried on `ClaudeCodeStats`. UI reads it in `DashboardView`. `LiveAccountUsageClient` gains an `onSetCookies` callback wired to `AccountAuth`.

**Tech Stack:** Swift 6, swift-testing, Swift Charts. Read the `dataviz` skill before chart code.

## Global Constraints

- Kiln: charts/data = terracotta family (`Theme.data`, `Theme.chartGradient`), chrome = `Theme.accent`; every new color a `Color(light:dark:)` pair; respect `accessibilityReduceMotion`.
- Privacy: only token counts/timestamps — no new fields beyond aggregates.
- Both variants must build: `swift build` and `swift build -Xswiftc -DAPPSTORE`.
- `make test` green (154 existing + new).

---

### Task 1: `IntradayProfile` + `DayEndForecast` (Kit, TDD)

**Files:**
- Create: `Sources/UsageMeterKit/ClaudeCode/DayEndForecast.swift`
- Test: `Tests/UsageMeterKitTests/DayEndForecastTests.swift`

**Interfaces (Tasks 2–3 rely on these exact names):**
```swift
public struct IntradayProfile: Codable, Sendable, Equatable {
    /// Average cumulative fraction of a day's tokens reached by each local
    /// hour boundary; 25 entries, [0]=0 … [24]=1, monotonic non-decreasing.
    public let cumulativeFraction: [Double]
    /// Population std-dev of the per-day fractions at each hour (25 entries).
    public let dispersion: [Double]
    /// Number of complete days that informed the profile.
    public let dayCount: Int
    public static func compute(records: [UsageRecord], now: Date, calendar: Calendar,
                               days: Int = 14, minDayTokens: Int = 1_000_000) -> IntradayProfile?
}
public struct DayEndForecast: Sendable, Equatable {
    public let projectedTokens: Int
    public let lowTokens: Int
    public let highTokens: Int
    public let projectedCost: Double?
    public static func compute(tokensToday: Int, costToday: Double?, now: Date,
                               calendar: Calendar, profile: IntradayProfile?) -> DayEndForecast?
}
```

Math:
- Profile: for each of the `days` complete local days before `now`'s day with
  total ≥ `minDayTokens`: bucket that day's record tokens by local hour, build the
  day's cumulative fraction at hours 0…24; average across days (simple mean) and
  take the population std per hour. Return nil if <3 qualifying days.
- Forecast fraction at `now`: linear interpolation between the two surrounding
  hour boundaries. `f = max(fraction, 0.05)`.
- `projected = Int(Double(tokensToday) / f)`; low/high use `min(1, f + σ)` /
  `max(0.05, f − σ)` where σ = interpolated dispersion (note: +σ ⇒ LOW estimate).
- Gates → nil: profile nil, `tokensToday <= 0`, or (local hour < 8 AND fraction < 0.15).
- `projectedCost = costToday.map { $0 / Double(tokensToday) * Double(projected) }`
  (blended rate; nil when costToday nil or tokensToday 0).

**Steps:** (TDD)
- [ ] Write `DayEndForecastTests` covering: profile from synthetic records (2 days
  identical shape → exact fractions, monotonic, dayCount), <3 days → nil,
  low-token days excluded, forecast midpoint math (half-day profile, half of
  tokens by noon → projected = 2×tokensToday), floor at 0.05, early-morning gate,
  band ordering (low ≤ projected ≤ high), blended cost.
- [ ] Run: `swift test --filter DayEndForecastTests` → FAIL (type not found).
- [ ] Implement `DayEndForecast.swift` per the math above.
- [ ] Run: `swift test --filter DayEndForecastTests` → PASS.
- [ ] Commit: `feat(kit): intraday profile + day-end forecast`

### Task 2: Carry the profile on `ClaudeCodeStats`

**Files:**
- Modify: `Sources/UsageMeterKit/Models/Aggregates.swift` (add
  `public var intradayProfile: IntradayProfile?` with default nil to
  `ClaudeCodeStats` + init param `intradayProfile: IntradayProfile? = nil`)
- Modify: `Sources/UsageMeterKit/ClaudeCode/DailyAggregator.swift:108` (compute
  `IntradayProfile.compute(records: unique, now: now, calendar: calendar)` and
  pass it)
- Test: extend `Tests/UsageMeterKitTests/DayEndForecastTests.swift` with one
  aggregator-integration test (aggregate fixture records → stats.intradayProfile != nil).

**Steps:**
- [ ] Failing integration test → implement → `make test` green → commit
  `feat(kit): expose intraday profile on ClaudeCodeStats`.

### Task 3: Dashboard — forecast card, MA line, projected bar, weekday card, animation

**Files:**
- Modify: `Sources/UsageMeter/Dashboard/DashboardView.swift`
- Modify: `Sources/UsageMeter/App/Theme.swift` (one new pair:
  `static let dataMuted = Color(light: 0x9A6B4F, dark: 0xB08968)` — MA line /
  de-emphasized weekday bars)

**Steps:**
- [ ] Read the `dataviz` skill (trigger: chart work).
- [ ] Forecast plumbing: `private var forecast: DayEndForecast?` computed from
  `model.snapshot.claudeCode` stats (`DayEndForecast.compute(tokensToday:
  stats.today.totalTokens, costToday: stats.todayEstimatedCost, now: Date(),
  calendar: .current, profile: stats.intradayProfile)`).
- [ ] Insights row gains a forecast card when non-nil: value
  `"~" + Formatting.tokens(forecast.projectedTokens)`, label
  `"On pace today · ≈ \(Formatting.cost(projectedCost))"` (or range caption
  `low–high` when cost nil). Icon `gauge.with.needle`, tint `.secondary`.
- [ ] History chart: on ranges 30D/90D/All add 7-day trailing MA
  `LineMark` (`Theme.dataMuted`, lineWidth 1.5, no symbols, `.interpolationMethod(.monotone)`);
  on 7D/30D, when forecast non-nil, add for TODAY only a translucent
  `BarMark(yStart: tokensToday, yEnd: forecast.projectedTokens)`
  (`Theme.data.opacity(0.18)`) + dashed `RuleMark(y: projectedTokens)` capped to
  today's x with annotation "projected".
- [ ] Weekday profile card under insights: compute from `allPoints` (last 84
  days) mean tokens per weekday; `Chart` of 7 `BarMark`s, weekday initials on x,
  today's weekday `Theme.data`, others `Theme.dataMuted.opacity(0.55)`; caption
  "Average by weekday · last 12 weeks". Hidden when all zero.
- [ ] Animation: wrap chart content values in `.animation(reduceMotion ? nil :
  .easeOut(duration: 0.5), value: range)` (existing) and animate the MA/projected
  marks via the same; bars grow on first appear only if `!reduceMotion` (existing
  `appeared` state).
- [ ] `swift build` + APPSTORE build; commit
  `feat: forecast card, MA trend, projected bar, weekday profile`.

### Task 4: Durable login — Set-Cookie write-back

**Files:**
- Modify: `Sources/UsageMeterKit/Account/LiveAccountUsageClient.swift`
- Modify: `Sources/UsageMeter/Account/AccountAuth.swift`
- Modify: `Sources/UsageMeter/App/AppModel.swift` (wire callback where
  `LiveAccountUsageClient` is constructed)
- Test: `Tests/UsageMeterKitTests/LiveAccountUsageClientTests.swift`

**Steps:**
- [ ] Failing test: mock URLProtocol response includes
  `Set-Cookie: sessionKey=new-value; Domain=claude.ai; Path=/; Expires=…` →
  expect `onSetCookies` called with a cookie named `sessionKey` (use a
  confirmation/actor box, existing harness patterns).
- [ ] Kit: add `onSetCookies: (@Sendable ([HTTPCookie]) -> Void)? = nil` init
  param; after `guard let http` succeeds (before status branching), extract:
  ```swift
  if let onSetCookies, let fields = http.allHeaderFields as? [String: String] {
      let cookies = HTTPCookie.cookies(withResponseHeaderFields: fields, for: url)
      if !cookies.isEmpty { onSetCookies(cookies) }
  }
  ```
- [ ] App: `AccountAuth.storeCookies(_ cookies: [HTTPCookie])` (main-actor):
  `for c in cookies { dataStore.httpCookieStore.setCookie(c) }`. AppModel passes
  `onSetCookies: { cookies in Task { @MainActor in auth.storeCookies(cookies) } }`.
- [ ] `make test` green, both builds; commit
  `feat: self-renewing login — write refreshed cookies back to the WebKit store`.

### Task 5: Verify + finish

- [ ] `make test`, both variants, `make app && make install`, relaunch.
- [ ] Screenshot dashboard (light+dark) — verify forecast card, MA line,
  projected segment, weekday card render sanely with real data.
- [ ] Update `docs/STATUS.md`; merge to main; push.
