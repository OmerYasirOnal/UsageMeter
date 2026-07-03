<p align="center">
  <img src="docs/icon.png" width="128" height="128" alt="UsageMeter app icon — a terracotta gauge">
</p>

<h1 align="center">UsageMeter</h1>

A small, fast, **native macOS menu-bar app** that means you never hit Claude
limits unexpectedly — free and private, no subscription, no telemetry.

It tracks three independent things:

- **Account (claude.ai)** — your real **session %**, **weekly %**, **weekly Opus %**,
  reset times, and **real pay-as-you-go spend**, straight from your own claude.ai
  account (after you log in).
- **Claude Code** — tokens, "API value", and per-model / per-project breakdowns read
  from local Claude Code logs. **No login, no network.**
- **Service status** — a live "Claude is up / degraded / down" badge from Anthropic's
  public status page.

> **Privacy is a hard rule.** UsageMeter reads only **token counts, model names, and
> timestamps** from your local logs — **never your messages**. For your account it
> reads only **usage percentages, reset times, and your own spend** — never
> conversation content. Everything stays on your Mac; nothing is sent anywhere.

---

## Screenshots

<p align="center">
  <img src="docs/screenshots/dashboard.png" width="780" alt="UsageMeter dashboard — live session and weekly limits, usage-history chart with a day-end projection and 7-day trend line, forecast and insight cards, and a weekly-rhythm chart">
</p>

<p align="center">
  <img src="docs/screenshots/popover.png" width="340" alt="UsageMeter menu-bar popover in the Kiln design — session hero with a reset countdown, weekly limit, and today's Claude Code tokens and API value">
</p>

---

## Download

**[⬇️ Download the latest release](https://github.com/OmerYasirOnal/UsageMeter/releases/latest)** —
grab `UsageMeter-macOS.zip`, unzip, and drag **UsageMeter.app** into your Applications folder.
Look for the gauge icon in the menu bar.

Or with **Homebrew**:

```bash
brew install --cask omeryasironal/tap/usagemeter
```

> The download is **signed with a Developer ID and notarized by Apple** (hardened
> runtime, stapled ticket), so it opens with a normal double-click — no Gatekeeper
> warning and no `xattr` workaround. An App Store release is also in the works.

Requires **macOS 15 (Sequoia) or later**. Prefer to build it yourself? See
[Build, run & install](#build-run--install).

---

## Features

- 🎛 **Menu-bar popover** — a session hero with a big reset countdown, weekly / Opus %,
  real spend, today's Claude Code tokens + API value, and a status dot. Optionally
  shows the session % or today's API value right in the menu bar.
- 📈 **Forecasts** — "at this pace you hit the limit in ~2h" burn projections, and a
  day-end forecast learned from *your own* daily rhythm ("on pace for ~420M tokens /
  ≈ $560 today").
- 📊 **Dashboard** — usage-history chart with hover tooltips and a 7-day trend line
  (7D / 30D / 90D / All), Insights cards incl. week-over-week change, a weekly-rhythm
  chart, a 12-month GitHub-style activity heatmap with month labels, by-model /
  by-project breakdowns. Export to **CSV** or a shareable **PNG**.
- 👥 **Team snapshots (serverless)** — each member exports a **stats-only**
  `.umteam` file; drop them on the dashboard's Team card to see the whole team
  (tokens, API value, 7-day Δ). No server, no accounts — nothing is transmitted.
- 🔔 **Smart notifications** — at 50 % / 75 % / 90 %, a smoothed burn-rate alert
  ("on track to hit your limit before it resets"), and a daily API-value budget.
- ✨ **Email-first login** — type your claude.ai email once; UsageMeter prefills and
  submits the sign-in form for you and shows the page only at the verification-code
  step, so you just paste the code. A native curtain fetches your numbers and closes
  the window in under a second, and the session self-renews so you stay logged in.
  (Google / SSO users can pick the full claude.ai sign-in page.)
- 🌗 **Appearance** — System / Light / Dark applied everywhere (popover included),
  launch-at-login, tabbed Settings, and a built-in update check for this download.
- 🔒 **Local-first & private** — three decoupled sources; the app stays fully useful
  even when you never log in (Claude Code + status still work).

## How it compares

`ccusage` and Claude Code's built-in `/usage` are both great — they solve
different halves of the problem. UsageMeter is the only one that lives in your
menu bar and shows *both* your local Claude Code cost **and** your real account
session / weekly limits, with history and forecasts.

| | **UsageMeter** | `ccusage` | `/usage` (built-in) |
|---|:---:|:---:|:---:|
| Always-visible native macOS menu bar | ✅ | ❌ (CLI) | ❌ (in-terminal) |
| Real account **session / weekly %** | ✅ | ❌ | ✅ |
| Claude Code **tokens & cost** (local logs) | ✅ | ✅ | ❌ |
| Usage **history, charts, heatmap** | ✅ | daily/monthly tables | ❌ |
| **Burn-rate forecasts** & notifications | ✅ | ❌ | ❌ |
| No Node / nothing to install | ✅ native app | ❌ needs Node | ✅ |
| Never reads message content | ✅ | ✅ | ✅ |
| Open source | ✅ MIT | ✅ | built-in |
| Price | Free | Free | Free |

Think of it as **"ccusage, but native — plus your actual account limits."**

## Requirements

- macOS 15 (Sequoia) or later (developed on macOS 26).
- Swift 6 toolchain (Xcode 26 or the matching command-line tools).

No third-party dependencies.

## Build, run & install

```bash
make test      # 180+ headless tests — no network or real data needed
make run       # build UsageMeter.app and launch it
make app       # just build ./UsageMeter.app
make install   # build and copy to /Applications
make xcodeproj # generate the Xcode app target for App Store archiving (needs XcodeGen)
```

You can also open the package in Xcode: **File ▸ Open… ▸ `Package.swift`**.

When running, look for the **gauge icon** in the menu bar; click it for the popover.

> **Why SwiftPM instead of an `.xcodeproj`?** Zero external tooling, the engine is
> testable headlessly with `swift test`, and the build is reproducible from the
> command line. `Scripts/make_app.sh` assembles a proper `.app` bundle (with
> `Info.plist` / `LSUIElement`) so launch-at-login and menu-bar behavior work like a
> normal app.

## How the account source works (and a Terms-of-Service note)

There is **no official public API** for the claude.ai consumer subscription
session / weekly %. The Usage page itself uses claude.ai's internal endpoint, so
any app showing these numbers reads that same endpoint with your own logged-in
session. UsageMeter does this transparently:

- **Login** in a `WKWebView` (we never see your password). Your session is stored in
  an isolated, app-private data store; **Log out** wipes it.
- **Empirical discovery** — a hook in the login window observes only **usage-shaped,
  first-party** API responses to learn the endpoint; it never touches conversation
  or account traffic.
- **Headless refresh** — the discovered endpoint is replayed with your cookies
  (scoped to that host) and decoded; it's isolated behind the `AccountUsageClient`
  protocol so breakage is contained and the app degrades to local-only mode.

⚠️ Automating authenticated access to claude.ai is a **Terms-of-Service grey area** —
review Anthropic's current Usage Policy / Terms before relying on it. Logging in is
entirely optional; the app is useful without it.

## Privacy

- **Source B (local logs):** only `type`, `isSidechain`, `requestId`/`uuid`,
  `timestamp`, `message.model`, and `message.usage.*` are read. Never message content.
- **Source A (account):** only usage percentages, reset times, and your own spend.
- Local caches live in `~/Library/Application Support/UsageMeter/` and never leave
  your machine. "Log out" wipes the account session and discovery files.

Full policy: [`PRIVACY.md`](PRIVACY.md) · [omeryasironal.github.io/UsageMeter/privacy.html](https://omeryasironal.github.io/UsageMeter/privacy.html)

## "API value" vs real spend

On a flat subscription, the dollar figure for Claude Code tokens isn't money you
spent — it's what those tokens **would** cost on the pay-as-you-go API ("API value"
= the value you get from your subscription). You can hide it in Settings. Your
**actual** spend is read from claude.ai and shown separately as "Pay-as-you-go used".

## FAQ

**How do I see my Claude weekly limit?**
Log in with your claude.ai email (Settings ▸ or the popover's Sign in). UsageMeter
then shows your **session %**, **weekly %**, weekly **Opus %**, and the exact reset
times — the same numbers as `claude.ai/settings/usage`, right in your menu bar.

**How do I check my Claude Code token usage and cost?**
That works with **no login and no network** — UsageMeter reads your local Claude
Code logs (`~/.claude`) and shows today's tokens, an estimated API-rate value, and
per-model / per-project breakdowns.

**Does UsageMeter read my conversations?**
No. It reads only token counts, model names, and timestamps — never message or
conversation content. That's a hard rule enforced in the parser and the on-disk
cache, and it's why the App Store privacy label is "Data Not Collected."

**Do I have to log in?**
Only if you want the account **session / weekly %**. Claude Code cost and the
service-status badge work fully offline without any account.

**Is my claude.ai login safe? What's stored?**
UsageMeter never sees your password — you sign in on claude.ai's own page. Only
your login **session cookie** is stored locally (in an isolated store), and
**Log out wipes it**. Nothing is sent anywhere.

**Is this official / affiliated with Anthropic?**
No. UsageMeter is an independent open-source project, not affiliated with or
endorsed by Anthropic. The account numbers come from claude.ai's own (unofficial,
undocumented) usage endpoint — see the Terms-of-Service note above.

**What's "API value" vs real spend?**
On a flat subscription, the dollar figure for Claude Code tokens isn't money you
spent — it's what those tokens *would* cost on the pay-as-you-go API. Your real
pay-as-you-go spend is read separately from claude.ai. See the section above.

**Isn't this just ccusage?**
ccusage is a great Node CLI for local Claude Code token/cost. UsageMeter is a
native menu-bar app that adds your **real account limits**, history, forecasts, and
notifications — with no Node to install. See [How it compares](#how-it-compares).

## Architecture

Three decoupled sources behind protocols, orchestrated by a `DataEngine` actor. See
[`CLAUDE.md`](CLAUDE.md) for the full architecture, the privacy rule, and the
Source-A caveat. The engine (`UsageMeterKit`) is 100 % headless-testable.

## Contributing

Contributions welcome — see [`CONTRIBUTING.md`](CONTRIBUTING.md). Please keep the
**privacy hard rule** intact: never read or persist message content.

## License

[MIT](LICENSE) © Omer Yasir Onal.

*Not affiliated with or endorsed by Anthropic. "Claude" is a trademark of Anthropic.*
