# Project Status & Handoff — UsageMeter

_Last updated: 2026-07-01. Read this first when resuming in a new session._

## ⭐ Resume point (where we left off)

**UsageMeter 0.2.0 (build 3) is SUBMITTED to the Mac App Store — state
`WAITING_FOR_REVIEW`, submitted 2026-07-01 14:32 UTC.** We shipped the **local-only
variant (Option A)**: the App Store build defines `APPSTORE`, which compiles out the
claude.ai account (Source A) + WebKit (verified stripped via `otool -L`). A
pre-submission multi-agent audit caught that the **full** account build (built +
uploaded earlier as build 2) would almost certainly be rejected — Guideline **5.2.2**
(automating the unofficial claude.ai endpoint, self-disclosed in the binary strings) +
**2.3.1** (metadata/privacy label describe the local-only app, not the account binary).
So we pivoted to local-only and **expired build 2** so it can't be submitted.

> **Next:** wait for Apple's review result (~24–48 h; email to the account-holder
> contact). Release is set to **auto-release after approval**. If rejected, the audit's
> SHOULD-FIX list is the playbook (affiliation disclaimer already added). Loose ends:
> branch **`appstore-local-only`** is pushed with a PR open into `main`; optional
> per-submission contact info was left blank (needs a phone) so Apple defaults to the
> account contact.

### What was done for this submission (2026-07-01)
- **Local-only build 3** — `SWIFT_ACTIVE_COMPILATION_CONDITIONS: APPSTORE`,
  `ITSAppUsesNonExemptEncryption=NO`; app target renamed **`UsageMeterApp`** to fix a
  scheme-name collision with the SwiftPM `.executable(name: "UsageMeter")` that had
  produced an EMPTY archive (surfaced as export "Unknown Distribution Error").
- **Runtime "Show sample data (preview)" toggle + banner** (Settings) so App Review
  sees a populated dashboard on a data-less Mac — fixes the 2.1 empty-state rejection.
  The demo gate now fires on the `USAGEMETER_DEMO` env var OR the persisted setting.
- **App Store Connect** (app `6786227263`, version `23ab8b3b`, review submission
  `f6f67f7d`): 2 local-only screenshots (dashboard + insights), description with the
  "not affiliated with Anthropic" disclaimer, keywords (dropped `anthropic`), App
  Review Notes, App Privacy = **Data Not Collected**, Age **4+**, Price **Free**,
  Content Rights = No, Copyright, PrivacyInfo reason `0A2A.1`→`3B52.1`. Automated via
  the ASC REST API (`scratchpad/asc.py`, key `93HFBMV3MA`) + Playwright for the
  web-only forms (age rating, price, privacy).

## Links

- **Repo:** https://github.com/OmerYasirOnal/UsageMeter (public, MIT)
- **Release v0.2.0 (Latest):** downloadable `UsageMeter-macOS.zip` (ad-hoc signed → first launch
  needs right-click ▸ Open, or `xattr -dr com.apple.quarantine`).
- **Privacy policy:** `PRIVACY.md` + GitHub Pages
  https://omeryasironal.github.io/UsageMeter/privacy.html (verify it's live — it was
  "building" when last checked).

## What's done

- **M1** — menu-bar shell + Source B engine (scanner/parser/pricing/aggregator/store,
  incremental, dedup, skips `subagents/` + `isSidechain`) + Source C status. Verified
  against the real `~/.claude/projects` (116 session files).
- **M2** — claude.ai account login (`WKWebView`, isolated `WKWebsiteDataStore`,
  logout wipes it). Endpoint discovered empirically:
  `GET https://claude.ai/api/organizations/{org}/usage`. **Email login reliable;
  Google works via a real popup window** (`createWebViewWith`). After login it
  auto-navigates to the Usage page and the window auto-closes on capture. Headless
  refresh via `LiveAccountUsageClient`, adaptive cadence, local-only fallback.
- **M3** — Dashboard (Swift Charts usage history w/ range filter, Insights cards,
  12-month activity heatmap, by-model/by-project, Claude Code summary, **CSV + PNG
  export**), **notifications** (50/75/90% + smoothed burn-rate), **appearance**
  (System/Light/Dark), launch-at-login, coral accent tint everywhere.
- **Account data is correct** — `utilization` is a **0..100 percent** (not a
  fraction); windows are primary, `limits[]` is the fallback. Real **spend** comes
  from `spend.used`; the Claude Code dollar figure is relabeled **"API value"**
  (subscription value, not real spend; toggle in Settings).
- **Open source** — README, CONTRIBUTING, MIT LICENSE, topics, v0.1.0 release.
- **Demo mode** — `USAGEMETER_DEMO=1` / `make demo` injects synthetic data for shots.
- **Confirmed-bug batch (2026-07-02)** — the 7 CONFIRMED bugs from the multi-agent
  deep review fixed in one batch (branch `fix/deep-review-bug-batch`, plan in
  `docs/superpowers/plans/2026-07-02-confirmed-bug-batch-fixes.md`): incremental
  cache survives relaunches (mtime tolerance); no-op refreshes no longer rewrite
  cache.json every tick (~13 MB/min saved); an empty scan (sandbox bookmark
  failure) can no longer wipe cached stats; pricing updated to official rates
  (opus 5/25, fable/mythos 10/50); `usage.cache_creation` TTL split parsed and 1h
  writes priced ×2 (cache v2→v3, one-time full re-parse); transient account
  failures serve the last good value for ≤30 min; auto-refresh survives the
  sample-data toggle. Remaining review findings (UX/perf/distribution) are in the
  review report, unfixed.
- **App Store 0.2.1 UX package (2026-07-02, ready to ship after Apple's 0.2.0
  verdict)** — fixes the review's three APPSTORE-build UX gaps (branch
  `feat/appstore-021-ux`, plan `docs/superpowers/plans/2026-07-02-appstore-021-ux-package.md`):
  popover empty state now offers the sandbox "Grant access to ~/.claude…" CTA
  (plus a "Scanning…" first-load state); account-dependent Settings/privacy copy
  is compiled out of the APPSTORE build; **notifications work locally** — new
  `DailyBudgetPolicy` (Kit, tested) alerts once/day when today's API value
  crosses a user-set budget (Settings ▸ Notifications, $0 = off), no account
  needed; APPSTORE menu bar defaults to showing today's API value. Both build
  variants verified (`swift build` and `swift build -Xswiftc -DAPPSTORE`).
  Version/build numbers NOT bumped yet — do that when submitting 0.2.1.
- **App Store 0.2.2 prepped (2026-07-02)** — decision: keep 0.2.0 in review
  (pulling it resets the queue + invites metadata mismatch); build 0.2.2 (5)
  (`APPSTORE` local-only variant) archived headlessly (xcodebuild + ASC API
  key) and UPLOADED to App Store Connect. Verdict-day checklist + What's-New
  copy: `docs/appstore-0.2.2-submission.md`. MVP policy unchanged (local-only
  store build; all new features are local so they ship in both variants).
- **v0.2.2 released + Homebrew tap (2026-07-02)** — notarized GitHub release
  `v0.2.2` (Kiln, curtain, forecasts, tabbed Settings, app-wide theme, update
  check, quartile heatmap, Team Stage 0). New public repo
  `OmerYasirOnal/homebrew-tap` → `brew install --cask omeryasironal/tap/usagemeter`
  (update the cask's version+sha256 on each release). ⚠️ Repeated same-day
  logouts: root-cause candidate = replay UA ≠ WebView UA (Cloudflare clearance
  is UA-bound) → replay now sends the Safari UA; cookie write-back UNWIRED
  (kit code+tests remain); os.Logger (subsystem com.omeryasir.usagemeter,
  category account) records auth transitions for the next incident.
- **Team snapshot Stage 0 (2026-07-02)** — branch `feat/team-snapshot`, spec
  `docs/superpowers/specs/2026-07-02-team-snapshot-design.md`: serverless
  team/admin first step. `TeamSummary` (`.umteam`, schemaVersion 1, stats-only —
  a test locks "no project/path leakage") + `TeamMemberRow` in Kit;
  Dashboard ▸ Export ▸ "Team summary (.umteam)"; Team card imports files
  (panel + drag-drop), persists copies under App Support/UsageMeter/team/
  (newer file per member wins), table (tokens/API value/7-day Δ/last active) +
  per-member bar chart. Stage 1 (Supabase backend, invites, consent flow)
  stays a separate spec cycle. Also this session: popover Settings button fixed
  (`openSettings` action), GitHub update check (daily silent + About button +
  popover row), heatmap quartile levels, VERSION bumped to 0.2.2 (5).
- **Settings rebuild + app-wide appearance + chart analysis (2026-07-02)** —
  branch `feat/settings-appearance`, spec
  `docs/superpowers/specs/2026-07-02-settings-appearance-analysis-design.md`:
  (1) theme override now applied as `NSApp.appearance` from AppModel (per-view
  `preferredColorScheme` removed) — **fixes the popover-window appearance
  quirk** at the root; window chrome/materials/menus all follow the setting;
  (2) Settings rebuilt as a tabbed panel (General / Data / Notifications /
  Account / About, width 560, version row in About; folders editor keeps its
  commit-on-focus-loss lifecycle, plus commit-on-tab-leave); (3) charts:
  hover tooltip on Usage History (nearest-day rule + material card),
  "+34% vs previous 7 days" week-over-week insight card
  (`DashboardMetrics.weekOverWeekChange`, complete-days windows, nil without a
  baseline), GitHub-style month labels on the Activity heatmap. 171 tests.
- **Forecast analytics + durable login (2026-07-02)** — branch
  `feat/forecast-analytics`, spec
  `docs/superpowers/specs/2026-07-02-forecast-analytics-design.md`: (1)
  `IntradayProfile` + `DayEndForecast` in Kit — day-end projection from the
  user's own 14-day intraday rhythm (honesty gates: ≥3 qualifying days,
  fraction floor 0.05, early-morning silence) surfaced as an "On pace today"
  insight card and a translucent projected-remainder segment + dashed rule on
  today's history bar (7D/30D); (2) 7-day trailing moving-average line
  (calendar-window, gaps count as zero; `Theme.dataMuted`) on 30D/90D/All;
  (3) "Weekly rhythm" card — average tokens by weekday over 12 weeks, today's
  weekday emphasized; (4) **durable login** — `LiveAccountUsageClient` hands
  Set-Cookie headers back (`onSetCookies`) and `AccountAuth.storeCookies`
  persists rotated/extended claude.ai session cookies into the WebKit store,
  so the login self-renews with every refresh instead of dying at the original
  cookie expiry. 169 tests. Visual pass on the new dashboard cards still owed
  (user was active; no synthetic screenshots taken).
- **Login-flow curtain (2026-07-02)** — branch `feat/login-curtain`, spec
  `docs/superpowers/specs/2026-07-02-login-flow-polish-design.md`: after sign-in
  the claude.ai usage page is never shown — a native "Signed in ✓ / Fetching your
  usage…" curtain covers the WebView while the hidden hop fires the capture, then
  the window closes in 0.8 s (was a visible 2.5 s dwell on the usage page). New
  `LoginFlowModel` phase reducer in Kit (10 tests; 154 total). 15 s timeout lifts
  the curtain with a Retry banner. Google hardening: live WKWebView harness proved
  the OAuth popup reaches Google's real sign-in page (no UA block at that stage);
  UA bumped to Safari 26.0 for the credential step, popup centered over the login
  window with live title, dev-era "Usage Page" toolbar button removed, window
  slimmed to 640×760. Live credentialed login still to be user-verified.
- **Kiln redesign + usability foundation (2026-07-02)** — branch `feat/kiln-design`,
  plan `docs/superpowers/plans/2026-07-02-kiln-design-foundation.md`, from the
  5-lens design review: duotone identity (teal chrome #0F766E/#2DD4BF +
  terracotta data ink #C2410C/#FB923C) replacing the borrowed Claude coral;
  adaptive light/dark tokens via `Color(light:dark:)` (old values failed WCAG
  contrast); color-as-state (numerals/menu-bar neutral until ≥75%); popover
  re-hierarchy (single session hero + big reset countdown, compact weekly rows,
  de-duped block/status/copy); keyboard shortcuts (⌘R/⌘,/⌘D/⌘Q/Esc); native
  card fills + heatmap opaque ramp; Reduce Motion + VoiceOver labels; en_US USD
  estimates; icon regenerated in fired terracotta. Known minor: the appearance
  override doesn't recolor the popover WINDOW (follows system; pre-existing).
  ⚠️ Bundle-ID unification (0.2.1) reset local settings + claude.ai login once.
- **Source-B performance trio (2026-07-02)** — branch `perf/source-b-trio`, plan
  `docs/superpowers/plans/2026-07-02-source-b-performance-trio.md`: (1)
  **append-offset parsing** — `CachedFile` carries `parsedBytes`/`parsedLines`;
  the active session file (60 MB ≈ 0.62 s/tick before) now parses only the
  appended tail; (2) **store-time dedup** — records stored once globally with
  deterministic sorted-path ownership (was 51,819 stored vs 21,591 unique ⇒
  ~2.4× smaller cache.json/memory/encode); file removals trigger a full rebuild
  so suppressed duplicates are recovered; (3) **lazy cache load** — the JSON
  decode moved out of `AppModel.init` (main thread) into first access inside the
  `DataEngine` actor. Cache v3→v4 (one-time rebuild).
- **Sandbox-ready** — `ClaudeFolderAccess` (security-scoped bookmark for `~/.claude`),
  additive (non-sandbox build unaffected); `UsageMeter.entitlements` provided.
- **Xcode target** — `project.yml` (XcodeGen) → `make xcodeproj`; `xcodebuild`
  BUILD SUCCEEDED. Only manual step: set Development Team, then Archive.
- **App icon** — `make icon` (`Scripts/make_icons.sh` + `Scripts/icon/render.swift`)
  generates the icon **from code** with pure CoreGraphics (headless, no display):
  a Claude-coral squircle + a bright filled gauge arc showing the consumption level
  (concept `gaugefill`, chosen unanimously by a 4-lens design panel). Each size is
  rendered **natively** so small sizes drop the track/needle and thicken the arc for
  16px legibility. Outputs `Resources/AppIcon.icns` (used by `make app`) and
  `Resources/Assets.xcassets/AppIcon.appiconset/` (used by the Xcode/App Store target,
  `ASSETCATALOG_COMPILER_APPICON_NAME: AppIcon`). Both build paths verified to embed
  the icon (`make app` → `CFBundleIconFile`; `xcodebuild` → `Assets.car` +
  `CFBundleIconName`).
- **144 tests pass** (`make test`). App installed at `/Applications/UsageMeter.app`.

## Build / run cheatsheet

```bash
make test       # 144 headless tests
make run        # build + launch UsageMeter.app
make install    # build + copy to /Applications
make demo       # launch with synthetic data (for screenshots)
make xcodeproj  # generate the Xcode app target (needs XcodeGen)
```

## Gotchas / key implementation notes

- **`utilization` is 0..100, NOT 0..1** — do not multiply by 100 (this caused a
  100%-everywhere bug). See `AccountUsageDecoder.decodeExact`.
- **Screenshots can't be auto-captured** in the agent env (no display; ImageRenderer
  headless breaks SF Symbols + ScrollViews). Use a real window via `make demo`.
- **`make app` = ad-hoc, unsandboxed** (for GitHub download). The **Xcode/`project.yml`
  path is the sandboxed App Store target.** Two build paths on purpose.
- **App icon is code-generated** — regenerate/tweak via `make icon` (edit
  `Scripts/icon/render.swift`; the `gaugefill` case is the shipping concept).
- **Menu-bar glyph = SF Symbol `gauge.with.dots.needle.50percent`.** ⚠️ We tried a
  custom `Canvas` mark (`GaugeGlyph`) but **`Canvas` does not render in a MenuBarExtra
  label** (AppKit snapshots the label to a *template image*; Canvas draws blank and
  breaks the layout so the % after it vanishes too). Reverted to the SF Symbol gauge
  (same family as the icon, templates + tints reliably, supports the live-% overlay).
  The custom gauge lives where it renders correctly: the **app icon** (CG-rendered
  `.icns`). If a custom menu-bar mark is ever wanted, pre-render it to a template
  PDF/PNG (`Image(...).renderingMode(.template)`), not a live `Canvas`.
- Login auto-close triggers on `auth.lastCaptured` (real usage capture), never while
  typing credentials.

## TODO (next session, roughly in order)

1. ~~**README screenshots**~~ — ✅ **done 2026-07-02**: captured from the REAL app
   with real data (per Yasir — no demo mode) via `screencapture -l <windowID>`
   (window IDs from `CGWindowListCopyWindowInfo`; popover opened by AppleScript-
   clicking the menu-bar item). `docs/screenshots/{dashboard,popover}.png`,
   embedded in README. Note: shots show real project names — re-capture if that
   ever becomes a concern.
2. **Verify the Pages privacy URL is live.**
3. ~~**App icon**~~ — ✅ **done** (code-generated `gaugefill`; `make icon`).
   Menu-bar glyph stays the SF Symbol gauge (Canvas can't render in a menu-bar label).
4. ~~**Notarize the GitHub download**~~ — ✅ **done 2026-07-02, shipped as v0.2.1.**
   Developer ID Application cert created (via the web portal with the CSR at
   `~/.appstoreconnect/developer_id/`; identity #4 in the login keychain, team
   9X8FDSW5D8), `make release-app` runs the full sign→notarize→staple→zip flow
   (notarytool profile `usagemeter-notary` / ASC key). v0.2.1 GitHub release is
   Developer-ID-signed + Apple-notarized + stapled — opens clean (verified with a
   quarantined-download simulation: `spctl` → "Notarized Developer ID"). App Store
   submission still pending (0.2.0 in review).
5. ~~**App Store scope decision**~~ — ✅ **done: Option A (local-only).** `#if APPSTORE`
   compiles out Source A (verified: WebKit not linked); `PrivacyInfo.xcprivacy`
   bundled; listing copy in `docs/APP_STORE_LISTING.md`. GitHub build stays full A+B+C.
6. ~~**App Store Connect** — app record, category, price, privacy label, screenshots,
   Archive → upload → Submit~~ — ✅ **done: SUBMITTED 2026-07-01 (build 3, local-only),
   `WAITING_FOR_REVIEW`.** Remaining: await review result; if approved it auto-releases.
7. **Optional polish** — GRDB/SQLite migration (large history), accessibility pass,
   Turkish localization, broader real-world testing, in-app "what's new".

## Recommendations (agent's opinion)

1. **Get the Apple Developer account first** — even before the App Store, it lets you
   **notarize the v0.1.x GitHub download** so users don't see the "unidentified
   developer" warning. That single step makes the free download feel trustworthy and
   is worth more short-term than the App Store.
2. **Ship the App Store build local-only** (Claude Code stats + status; no claude.ai
   login). It approves cleanly, markets honestly as "100% private, no account needed,"
   and the full A+B+C build stays on GitHub for power users. Attempt the full build on
   the App Store only later, with review history behind you.
3. **Keep "Data Not Collected" front and center** — it's true and a real
   differentiator vs paid alternatives.
4. **Treat Source A as inherently fragile** — it's an unofficial endpoint. The
   `account_capture.json` / `account_discovery.json` mechanism is the debugging tool
   when the shape changes; keep the heuristic fallback. Don't over-invest in Source A
   for the App Store version.
5. **Screenshots + an app icon are the highest-leverage polish** for perceived
   quality right now — small effort, big "real product" payoff.
6. **Don't rush submission.** Order: notarize download → icon → screenshots → decide
   App Store scope → submit. Everything technical is already in place.
