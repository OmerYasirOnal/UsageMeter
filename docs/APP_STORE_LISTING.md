# App Store listing — copy to paste into App Store Connect

This is for the **local-only** App Store build (Option A — no claude.ai login).
The listing must describe **only what that build does**: Claude Code stats +
service status. Do **not** mention the account session/weekly % feature — it's
compiled out of the App Store build (it lives only in the GitHub download).

---

**App Name:** UsageMeter  _(check availability in App Store Connect)_
**Subtitle** (≤30 chars): `Private Claude usage tracker`
**Primary category:** Developer Tools   ·   **Secondary:** Utilities
**Price:** Free
**Bundle ID:** `com.omeryasironal.usagemeter`

**Promotional text** (≤170 chars):
> Watch your Claude Code usage right from the menu bar — tokens, cost, and a "when will you run out?" projection. 100% private; nothing ever leaves your Mac.

**Description:**
> UsageMeter is a small, fast, native macOS menu-bar app that tracks your Claude Code usage — so you always know where you stand.
>
> Read straight from your local Claude Code logs:
> • Today's tokens and estimated API-rate value
> • Per-model and per-project breakdowns
> • A 5-hour block view with a "when will you run out?" burn projection
> • A full dashboard — usage history, a 12-month activity heatmap, CSV / PNG export
> • A live "Claude is up / degraded / down" badge from Anthropic's public status page
>
> Private by design — and that's the whole point:
> • Reads only token counts, model names, and timestamps — never your messages.
> • No telemetry. No account. No server. Nothing leaves your Mac.
> • Open source (MIT).
>
> Menu-bar only. On first run you grant read access to your `~/.claude` folder once.

**Keywords** (≤100 chars):
`claude,ai,usage,tokens,menu bar,developer,anthropic,claude code,cost,tracker,llm,monitor`

**Support URL:** https://github.com/OmerYasirOnal/UsageMeter/issues
**Marketing URL:** https://github.com/OmerYasirOnal/UsageMeter
**Privacy Policy URL:** https://omeryasironal.github.io/UsageMeter/privacy.html

**App Privacy ("nutrition label"):** **Data Not Collected** — no data types collected,
no tracking. (Backed by `Resources/PrivacyInfo.xcprivacy`.)

**Screenshots (1280×800 or 1440×900, ≥1):**
Show the **local-only** experience — the popover's *Claude Code — Today* + *5-hour
block* (with the burn projection) and the **Dashboard** (Usage History chart,
insights, activity heatmap). **Do NOT** show the account session/weekly % section —
it isn't in the App Store build. Capture from the demo for PII-free data (see
`docs/STATUS.md` for the demo/dashboard capture commands).

> Note: `make demo` runs the *full* (non-App-Store) build and injects a synthetic
> account, so its popover shows the account %. For true App-Store screenshots, run
> the **Xcode/local-only target** (`make xcodeproj` → run) — the account section is
> absent there — or crop to the Claude Code / Dashboard areas.
