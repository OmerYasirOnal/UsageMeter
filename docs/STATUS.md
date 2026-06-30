# Project Status & Handoff — UsageMeter

_Last updated: 2026-06-30. Read this first when resuming in a new session._

## ⭐ Resume point (where we left off)

The app is **feature-complete (M1 + M2 + M3)**, **open-sourced + released**, and
**technically App-Store-prepped (not submitted)**. ✅ **App icon now done** — a
code-generated coral gauge (`gaugefill`), wired into both build paths (see
"What's done"). The immediate next step is:

> **Add screenshots to the README.** The demo (`make demo`, synthetic/PII-free data)
> must be captured from a **real window** (Cmd-Shift-4 → Space → click). The agent
> environment has no display access and `ImageRenderer` botches SF Symbols/ScrollViews
> headlessly, so Yasir captures; the agent embeds into `docs/screenshots/` + README.

We deliberately have **not** submitted to the App Store yet — more polish first
(see TODO).

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
  `Scripts/icon/render.swift`; the `gaugefill` case is the shipping concept). The
  menu-bar glyph is still the SF Symbol `gauge.with.dots.needle` (same gauge family,
  supports the live-% overlay) — a custom monochrome menu-bar template is an optional
  follow-up, not done.
- Login auto-close triggers on `auth.lastCaptured` (real usage capture), never while
  typing credentials.

## TODO (next session, roughly in order)

1. **README screenshots** — Yasir captures demo (popover + dashboard); agent commits
   to `docs/screenshots/` and embeds in README. _(blocked on capture)_
2. **Verify the Pages privacy URL is live.**
3. ~~**App icon**~~ — ✅ **done** (code-generated `gaugefill`; `make icon`). Optional
   follow-up: a custom monochrome menu-bar template image.
4. **Apple Developer Program ($99/yr)** — unlocks (a) **notarizing the GitHub
   download** (removes the scary Gatekeeper warning) and (b) App Store submission.
5. **App Store scope decision** — local-only (recommended, clean approval) vs full
   (Source A, review risk). If local-only: add `#if APPSTORE` to compile out the
   claude.ai login.
6. **App Store Connect** — app record, category (Developer Tools), price Free, privacy
   label **"Data Not Collected"**, screenshots, set Dev Team in Xcode → Archive →
   upload → Submit. See `docs/APP_STORE.md`.
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
