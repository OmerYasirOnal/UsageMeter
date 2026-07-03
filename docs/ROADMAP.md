# UsageMeter — Post-v1.0 Roadmap (2026-07-03)

UsageMeter v1.0.0 is live on every channel: the notarized full variant on GitHub + Homebrew, and the local-only variant WAITING_FOR_REVIEW on the Mac App Store with auto-release. The next 8 weeks are about three things, in order: don't lose what we have (process + risk hardening), convert the one-time launch window (Apple approval fires the starting gun), and then deepen the product where it's uniquely valuable (limit history + pacing).

## Now (next 1-2 weeks)

**1. Rescue the ASC scripts + repo hygiene — S.** `asc.py`, `submit.py`, and `build_v1.sh` exist only in a session scratchpad that will be garbage-collected; losing them turns the next MAS submission into a re-derivation. Move them into `Scripts/release/` under version control today, gitignore `UsageMeter-macOS.zip` / `UsageMeter.app` / `build/` / stray PNGs, and split the 280-line STATUS.md into a short current-state file plus a changelog. This is first because it's the only item where waiting destroys something.

**2. GitHub Actions CI on both variants — S.** A macOS-runner workflow running `swift test`, `swift build`, and `swift build -Xswiftc -DAPPSTORE` on every push. The APPSTORE variant has already silently diverged once (WebKit linkage, compiled-out Settings copy); with 187 tests and zero automation, this is the biggest process gap and it protects every item below. Add `xcodegen && xcodebuild` for the store target if the runner cooperates; don't block on it.

**3. Trademark and brand-guideline sweep — S.** Audit README, repo description/topics, cask description, App Store metadata, privacy page, and screenshots against Anthropic's brand guidelines; ensure "Claude" is only used descriptively and the "not affiliated with Anthropic" disclaimer appears on every surface (currently confirmed only on the App Store listing). Must land **before** the launch posts multiply exposure — a trademark complaint post-HN-frontpage is the one non-technical event that can take down all channels at once.

**4. ToS review + informed-consent interstitial on account login — S.** Do the CLAUDE.md-mandated review of Anthropic's current Usage Policy/ToS and record the date and conclusions in `docs/`; add a one-time "this uses an unofficial claude.ai endpoint / only session cookies stored / logout wipes everything — I understand" sheet before the WKWebView login. This makes the honest framing the launch depends on actually true, not just claimed.

**5. Launch prep: README comparison table + FAQ — S.** An honest UsageMeter vs ccusage vs raw `/usage` table (native menu bar, real account %, no Node, notifications, privacy) and an FAQ with the literal questions people search ("how do I see my Claude weekly limit"). Must be merged before launch traffic arrives; it keeps capturing "ccusage but native" searchers indefinitely afterward.

**6. Launch week: Show HN + r/ClaudeAI + r/macapps — S, gated on Apple approval.** The moment 1.0.0 auto-releases, run the 3-day sequence: "Show HN: UsageMeter — a native Mac menu-bar meter for Claude limits (free, open source, never reads your messages)", then the subreddits. Lead with the 5-hour-limit pain and the privacy hard rule; be upfront in comments about the unofficial endpoint — HN rewards that. Do **not** stack Product Hunt the same day; it follows 2-3 weeks later.

**7. Source-A contract canary — S.** Freeze the redacted real capture as a versioned fixture for `AccountUsageDecoder.decodeExact`, add a decode-drift detector (exact path fails, heuristic walker succeeds → log + a subtle "degraded" badge instead of silently wrong numbers), and write the re-capture runbook. Confidently wrong headline numbers are the single worst failure mode for a trust-positioned app, and launch traffic maximizes the blast radius — this ships before or during launch week.

## Next (weeks 3-8)

**8. Account usage history: persist Source-A snapshots — M.** Every headless refresh already fetches session/weekly/Opus % and spend; persist each capture as tiny timestamped records in a new store file (decoupled, like `status.json`) and add a dashboard card: utilization over time, limit-hits per week, "you hit your session cap 3x last week, usually ~15:00". This answers the biggest question the app can't answer today and is the data foundation the pace card and any future forecasting build on — build the store first, fancy analytics later.

**9. Weekly pace card — S.** "Week is 40% elapsed, you've used 62% — at this pace you run out Friday ~18:00; sustainable pace is ~9%/day." All inputs come free from `seven_day` utilization + `resets_at`, and the smoothing math already exists in `NotificationPolicy`. This is the screenshot-able differentiator and the headline feature of 1.0.1.

**10. Menu-bar metric picker + right-click status-item menu — S.** Session %, weekly %, reset countdown, today's tokens/API value, or icon-only in the menu bar; right-click gives Refresh / Dashboard / Settings / Quit. Twice-parked, table-stakes polish for a Mac menu-bar utility, and exactly what new post-launch users notice first.

**11. 1.0.1 fast-follow submission: What's New + rating prompt + phased release — M, gated on the 1.0.0 verdict.** Bundle items 8-10 into a small MAS 1.0.1: `SKStoreReviewController` gated on a positive moment (3rd dashboard open across 7+ days, never after a notification), the parked in-app What's New sheet, phased release on. Screenshots stay strictly local-only per the 2.3.1 lesson. Converts launch-week installs into ratings while the listing is fresh.

**12. Timeboxed spike: Claude Code's own OAuth usage endpoint — M, hard-capped at one week.** Claude Code shows session/weekly limits via `/usage`, so an OAuth-token-backed usage endpoint on api.anthropic.com exists and its credentials already sit in `~/.claude`. Capture what Claude Code calls and prototype a second `AccountUsageClient` behind the existing protocol. If it works, it replaces the ToS-grey cookie replay — the single biggest strategic risk to the app. Run this after launch week (not during — no bandwidth for a Source-A incident mid-launch), and accept "no" as a valid outcome.

## Later / strategic bets

**13. Product Hunt launch — S.** 2-3 weeks after HN, with the pace card and history in screenshots. Second bite at the apple, not part of launch week.

**14. Promote the OAuth client to primary Source A — M-L, contingent on the spike.** If #12 succeeds, ship it as the default with cookie replay as fallback, then eventually delete the replay path. This de-risks the app's headline feature permanently.

**15. Accessibility pass + TR localization — M.** Worth doing once the post-launch feature set stabilizes; localizing twice is waste. Accessibility first (VoiceOver on the popover/dashboard), then strings.

**16. Team Stage 1 (Supabase backend + consent flow) — L.** Stays parked until there's demonstrated pull from Stage 0's serverless `.umteam` flow (actual users asking for live team views). Needs its own spec cycle; a backend also complicates the "Data Not Collected" story, so it must be opt-in and separately framed.

**17. Official Admin Cost API for API-key spend — M.** The one officially-supported data source we don't use; valuable for developer-audience users, but it's a new audience segment — validate demand from launch feedback first.

## Explicitly NOT doing (and why)

**Multi-provider support (OpenAI/Gemini).** The moat is being the best *Claude* meter — native, private, correct. Going multi-provider now triples the endpoint-fragility surface (three unofficial APIs instead of one) before the first one is even de-risked, and dilutes the launch positioning. Revisit only after #14 resolves Source A's foundation.

**GRDB migration.** `cache.json` v4 with incremental scan works, is tested, and has no user-visible pain. A storage rewrite is pure risk with zero user value right now; the new Source-A history store (#8) is small enough for Codable too. Reconsider only if cache size or query needs actually hurt.

**Remote kill-switch / phone-home manifest for Source A.** The decode-drift canary (#7) covers the real need locally. A remote manifest adds a phone-home surface that sits directly at odds with "Data Not Collected" and "nothing is sent anywhere" — the brand cost exceeds the operational benefit for a solo-maintained app.

**Same-day multi-platform launch stacking (PH + HN together).** Splitting launches 2-3 weeks apart gets two traffic spikes and lets the PH listing show post-HN social proof; stacking them gets one blurry spike and no second chance.

**Tool-call / message-count analytics.** Intentionally omitted for privacy — counting messages requires touching records the privacy hard rule says we never read. The "never reads your messages" claim is worth more than any chart it would enable.