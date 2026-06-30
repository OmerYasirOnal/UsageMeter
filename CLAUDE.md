# CLAUDE.md — UsageMeter project memory

A native macOS **menu-bar app** that tracks Claude usage. Swift 6 + SwiftUI,
menu-bar-only (`LSUIElement`), built with SwiftPM (+ an XcodeGen target for the App Store).

> 📍 **Resuming?** Read [`docs/STATUS.md`](docs/STATUS.md) first — it has the current
> state, the next-step TODO, and recommendations. **TL;DR:** M1+M2+M3 done,
> open-sourced + released (github.com/OmerYasirOnal/UsageMeter, v0.1.0), App-Store-prepped
> but **not submitted**. App icon **done** (code-generated `gaugefill`; `make icon`).
> Next: README screenshots (capture demo via `make demo`), then notarize the download /
> App Store. 113 tests pass.

## Architecture: three decoupled sources

The app has **three independent data sources** and must stay useful with any
subset available ("local-only mode" when not logged in).

- **Source A — Account (claude.ai) — PRIMARY / headline numbers.**
  Real session %, weekly %, weekly Opus %, reset times. ⚠️ Unofficial endpoint +
  ToS grey area. **Isolated behind `AccountUsageClient` (protocol).** **Implemented
  in M2**: `WKWebView` login on an isolated `WKWebsiteDataStore`; a usage-only,
  first-party capture hook discovers the endpoint empirically; `LiveAccountUsageClient`
  replays it headlessly with host-scoped cookies. Degrades to `LocalOnlyAccountUsageClient`-style
  local-only mode (`nil`) when logged out / endpoint unknown / 401-403 / decode-fail.
- **Source B — Local Claude Code logs — ROBUST / no auth, no ToS risk.**
  Tokens, estimated cost, per-model/per-project breakdowns from
  `~/.claude/projects/<slug>/<session>.jsonl`. **Fully implemented in M1**, behind
  the `ClaudeCodeSource` protocol (so all three sources are protocol-decoupled).
- **Source C — Status page — PUBLIC / trivial.**
  Badge from `https://status.claude.com/api/v2/summary.json`. **Implemented in M1.**

Decoupling is enforced: `DataEngine` (an `actor`) runs each source independently;
a failure in one never breaks the others.

## Privacy hard rule (also a selling point — state it in UI + README)

**Never read or store conversation text.** Source B reads ONLY: `type`,
`isSidechain`, `requestId`/`uuid`, `timestamp`, `message.model`, and
`message.usage.*`. The parser (`JSONLParser`) and the persisted `UsageRecord` are
the enforcement points — `UsageRecord` has no field that could hold content.
Verified: the on-disk cache contains only `id/model/projectID/timestamp/usage`.

The local cache (`~/Library/Application Support/UsageMeter/`) is keyed by absolute
session-file paths and stores the Claude Code project slug (which encodes the
project path incl. the macOS username) for labels — still **no message content**.
It never leaves the machine.

## Source-A ToS caveat (handle honestly — do not fake)

The claude.ai usage endpoint is **unofficial/undocumented** and automating
authenticated access is a **Terms-of-Service grey area**. Mitigations baked in:
- All risk is behind the `AccountUsageClient` protocol (one swappable file).
- Local-only fallback (B + C) keeps the app fully useful if A breaks or is unused.
- Only session cookies are ever stored (M2); logout must be trivial.
- Before shipping M2, Yasir should review Anthropic's current Usage Policy / Terms.

## Layout

- `Sources/UsageMeterKit/` — headless, 100%-testable engine (library).
  - `Models/` — `TokenUsage`, `ModelFamily`, `UsageRecord`, aggregates, `UsageBlock`,
    `AccountUsage`, `ServiceStatus`.
  - `ClaudeCode/` — `ClaudeCodeSource` (protocol) + `LocalClaudeCodeSource` (owns the
    Source-B pipeline + its incremental cache), `ProjectScanner` (incremental by
    mtime/size), `JSONLParser` (tolerant, dedup, skips sidechain), `Pricing`,
    `CostCalculator`, `DailyAggregator`, `BlockBuilder`, `ProjectName`.
  - `Status/` — `StatusClient` (protocol), `StatusDecoder` (testable), `LiveStatusClient`.
  - `Account/` — `AccountUsageClient` (protocol) + `LocalOnlyAccountUsageClient`;
    `LiveAccountUsageClient` (headless replay), `AccountUsageDecoder` (heuristic,
    to be tightened from the real capture), `AccountRefreshPolicy` (adaptive
    cadence), provider protocols + `AccountHosts` first-party allowlist. App side:
    `AccountAuth` (WebKit cookies/capture/logout) + `AccountLoginView`.
  - `Store/` — `UsageStore` (Source-B Codable cache, `cache.json` v2) and
    `StatusStore` (Source-C last-good status, `status.json`) — separate files so the
    sources are decoupled in persistence too. GRDB is a planned M3 upgrade.
  - `Engine/` — `DataEngine` (actor; injects all three source seams) + config/snapshot types.
  - `Resources/pricing.json` — editable rate table (ESTIMATES; verify officially).
- `Sources/UsageMeter/` — thin SwiftUI shell (`@MainActor AppModel` bridges to the actor).
- `Tests/UsageMeterKitTests/` — 75 fixture/mock-based unit tests (dedup, cost, block
  math, status decoding, incremental scan, store round-trips, DataEngine end-to-end
  orchestration) — no live network or real user data required.

## Build / run

- `make test` → `swift test` (75 tests, headless, no network/real-data needed).
- `make app`  → assembles `UsageMeter.app` (release) with a proper `Info.plist` + icon.
- `make icon` → regenerates the app icon **from code** (pure CoreGraphics, headless)
  → `Resources/AppIcon.icns` + `Resources/Assets.xcassets/AppIcon.appiconset/`. Edit
  the design in `Scripts/icon/render.swift` (shipping concept = the `gaugefill` case).
- `make run`  → assembles and launches the menu-bar app.
- Opens in Xcode 26 via `File ▸ Open` on `Package.swift`.

## Key implementation notes

- **Dedup is global** (across files), done in `DailyAggregator`, keyed by
  `requestId ?? uuid`. The parser may emit intra-file dupes; the aggregator removes them.
- **Sidechain/subagent work is skipped twice**: `ProjectScanner` skips any
  `subagents/` path, and `JSONLParser` skips `isSidechain == true` records. (On a
  real machine ~97% of `.jsonl` files are under `subagents/`.)
- **Incremental scan**: `UsageStore` caches parsed records per file keyed by
  path + (mtime, size); unchanged files are never re-read.
- **Cost model** (per 1M tokens): input×rate, cache-write×rate×1.25,
  cache-read×rate×0.10, output×outputRate. Unknown families (incl. `<synthetic>`)
  → cost `n/a`.
- **Pricing loading**: the app uses `Pricing.loadFromMainBundle()` (reads
  `Contents/Resources/pricing.json`, falls back to built-in defaults — never
  crashes). `Pricing.loadBundled()` (uses `Bundle.module`) is for tests/`swift run`.
- **Day grouping** uses the local calendar (what a user means by "today"); the
  5-hour block math uses UTC hour boundaries (matches Claude Code billing windows).

## Roadmap (do NOT build ahead of the milestones)

- **M2 (done)**: WKWebView login to claude.ai (Safari UA + popup handling for OAuth;
  email is the reliable path, Google is best-effort), isolated cookie persistence,
  `LiveAccountUsageClient` headless replay, adaptive refresh, local-only fallback.
  Window activation policy flips to `.regular` while a window is open so login/
  dashboard/settings focus properly (fixes the menu-bar-app focus/blank-screen bug);
  the login window auto-closes once usage is captured. `make install` copies to
  /Applications.
  - **Real endpoint (discovered empirically):** `GET https://claude.ai/api/organizations/{orgId}/usage`.
  - **Response shape:** `five_hour`/`seven_day`/`seven_day_opus`/`seven_day_sonnet`
    each `{ utilization, resets_at }`. ⚠️ **`utilization` is ALREADY a 0..100 percent**
    (verified: `five_hour`=39 ⇒ "Current session 39%") — do NOT multiply by 100.
    There is also an authoritative `limits: [{ kind, group, percent(0..100),
    resets_at, is_active }]` array (the values the Usage page shows; note `is_active`
    can be false yet still displayed). Plus `spend.used { amount_minor, currency,
    exponent }` = REAL pay-as-you-go spend, and `extra_usage`/`prepaid` credits.
    `AccountUsageDecoder.decodeExact`: windows are primary (utilization used as-is),
    `limits` fill any missing category (Opus); heuristic walker is the last fallback.
  - **Cost framing:** Claude Code token "cost" is API-equivalent **value** (relabeled
    "API value", toggle in Settings) — NOT the user's spend on a flat subscription.
    Real spend comes from `spend.used`. There is no public API for the consumer
    session/weekly %; for API-key (developer) spend the official Admin Cost API could
    be added.
- **M3 (largely done)**: Dashboard (Swift Charts usage history w/ range filter,
  Insights cards, 12-month Activity heatmap, by-model/by-project, Claude Code
  summary), CSV + PNG (ImageRenderer) export, appearance (system/light/dark),
  notifications (50/75/90% + smoothed burn-rate via `NotificationPolicy`/`UsageNotifier`),
  adaptive refresh, `make install` → /Applications. Window activation policy is
  derived from visible titled windows (`WindowPresentation`) so focus/lifecycle is
  robust across all close paths. Remaining/optional: GRDB migration, tool-call/
  message counts (intentionally omitted for privacy), official Admin Cost API for
  developer-API spend.
- **Notifications caveat**: burn-rate uses a rate smoothed from the cycle start
  (not a 2-sample slope) with a ≥30-min observation gate + ≥25% floor, and the
  per-cycle de-dup key is the reset time quantized to the hour — both to avoid the
  weekly-window false-positive / spam failure modes.
