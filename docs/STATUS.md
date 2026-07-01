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
- **Release v0.1.0:** downloadable `UsageMeter-macOS.zip` (ad-hoc signed → first launch
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
- **113 tests pass** (`make test`). App installed at `/Applications/UsageMeter.app`.

## Build / run cheatsheet

```bash
make test       # 113 headless tests
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

1. **README screenshots** — Yasir captures demo (popover + dashboard); agent commits
   to `docs/screenshots/` and embeds in README. _(blocked on capture)_
2. **Verify the Pages privacy URL is live.**
3. ~~**App icon**~~ — ✅ **done** (code-generated `gaugefill`; `make icon`).
   Menu-bar glyph stays the SF Symbol gauge (Canvas can't render in a menu-bar label).
4. **Apple Developer Program ($99/yr)** — unlocks (a) **notarizing the GitHub
   download** (removes the scary Gatekeeper warning) and (b) App Store submission.
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
