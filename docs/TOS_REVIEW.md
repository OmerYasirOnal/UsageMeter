# Terms-of-Service review — Source A (claude.ai account usage)

**Reviewed: 2026-07-03.** Factual extract of Anthropic's current public policies as
they relate to UsageMeter's Source A. **This is not legal advice and not a
compliance verdict** — it is raw material for Yasir's decision (the CLAUDE.md-
mandated review). Re-check the live pages before every release; the dates below are
the versions in force when this was written.

## What Source A actually does

`LiveAccountUsageClient` replays `GET https://claude.ai/api/organizations/{orgId}/usage`
**headlessly**, using the user's own session cookies (captured from a real WKWebView
login), on an adaptive schedule — i.e. **automated/scripted access to claude.ai
that is not through an Anthropic API key.** It reads only usage numbers, never
message content, and only the user's own account.

## Relevant clauses (verbatim)

### Consumer Terms of Service — effective **October 8, 2025**
Source: https://www.anthropic.com/legal/consumer-terms — **§3 "Use of our Services"**, prohibited activities:

> "Except when you are accessing our Services via an Anthropic API Key or where we
> otherwise explicitly permit it, to access the Services through automated or
> non-human means, whether through a bot, script, or otherwise."

> "To crawl, scrape, or otherwise harvest data or information from our Services
> other than as permitted under these Terms."

> "To decompile, reverse engineer, disassemble, or otherwise reduce our Services to
> human-readable form, except when these restrictions are prohibited by applicable
> law."

### Usage Policy — effective **September 15, 2025**
Source: https://www.anthropic.com/legal/aup — **"Do Not Abuse our Platform"**:

> "Utilize automation in account creation or to engage in spammy behavior"

> "Model scraping / distillation … without prior authorization"

(The Usage Policy's automation language is aimed at account-creation abuse and model
distillation, not read-only usage checks. The material clause is the Consumer Terms
§3 automated-access one above.)

## The tension (stated plainly)

The Consumer Terms §3 automated-access clause **appears to directly cover what
Source A does**: it accesses claude.ai "through automated or non-human means … a
script," and the only carved-out exception is access "via an Anthropic API Key." The
"crawl/scrape/harvest" clause is also arguably implicated (it reads data from the
service outside the normal UI). Reading only one's own usage numbers, with no message
content and no model scraping, is far from the abuse the Usage Policy targets — but
that is a mitigating framing, **not** an exception written into the terms.

This is a real decision, not a formality. Options, for the record:

1. **Keep Source A, add an explicit informed-consent gate** before login (the app
   already documents the grey area in README/PRIVACY; the gate makes the *user's*
   acceptance explicit). Lowest effort; does not remove the underlying tension.
2. **Gate Source A behind a clearly-marked, off-by-default "experimental" switch.**
3. **Pivot to an officially-sanctioned source** — ROADMAP #12: prototype the OAuth
   usage endpoint Claude Code itself calls (credentials already in `~/.claude`). If
   it works it replaces the cookie replay and removes this tension entirely. This is
   the durable fix.
4. **Drop Source A from distributed builds** and keep only Claude Code logs + status
   (the App Store variant is already exactly this).

Note: the **App Store build excludes Source A entirely** (`#if !APPSTORE`), so this
tension does **not** touch the Mac App Store submission — it applies only to the
GitHub/Homebrew full variant.

## Decision

- Date decided: 2026-07-09
- Choice: Option 1 — keep Source A, add an explicit informed-consent gate before login.
- Rationale: lowest-effort mitigation that makes the ToS tension explicit to the
  user rather than only documented in README/PRIVACY prose; the app is already
  live and being promoted, so an immediate mitigation matters more than a
  perfect one. Option 3 (OAuth pivot, ROADMAP #12) remains the tracked durable
  fix — this consent gate is not a substitute for it, just the interim
  mitigation. Implemented in
  `docs/superpowers/plans/2026-07-09-source-a-consent-gate.md`.

**Known scope limitation (2026-07-09, consciously accepted):** the consent gate
only fires when the login window is freshly opened at the `.consent` phase — it
does NOT gate the app's existing background account-refresh
(`LiveAccountUsageClient`, wired unconditionally in `AppModel.swift`). A user who
was already logged in to claude.ai *before* upgrading to this version never sees
the new disclosure; they'd only encounter it by explicitly logging out and back
in. This is accepted as-is for now (the original spec was scoped to "before
login," not migrating already-authenticated sessions) rather than expanding scope
mid-implementation. Revisit if/when Source A's auth mechanism changes (see
ROADMAP #12, the OAuth pivot).
