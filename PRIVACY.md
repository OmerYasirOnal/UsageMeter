# Privacy Policy — UsageMeter

_Last updated: 2026-06-30_

**Short version: UsageMeter does not collect, transmit, store on any server, or
share any of your data. There is no analytics, no telemetry, no tracking, no
third-party SDKs, and no account on our side. Everything stays on your Mac.**

## What UsageMeter reads (locally, on your Mac only)

- **Claude Code logs (`~/.claude/projects`)** — only `type`, `isSidechain`,
  `requestId`/`uuid`, `timestamp`, the model name, and the token-count fields of
  `message.usage`. **It never reads or stores your messages / conversation content.**
- **Your claude.ai account (only if you choose to log in)** — only your usage
  percentages, reset times, and your own pay-as-you-go spend. **Never conversation
  content.** UsageMeter never sees your password; only your claude.ai **session
  cookie** is stored locally, and **Log out** wipes it.
- **Service status** — Anthropic's public status page (`status.claude.com`). No
  personal data is involved.

## Where your data lives

Local caches are stored in `~/Library/Application Support/UsageMeter/` (or, in the
sandboxed Mac App Store build, the app's private container). **None of it ever
leaves your Mac.** Uninstalling the app or choosing **Log out** removes the relevant
local data.

## Network access

UsageMeter makes network requests only to:

- `status.claude.com` — the public service-status page; and
- `claude.ai` — **only if you log in**, and only to your own account, to read the
  same usage numbers shown on `claude.ai/settings/usage`.

Nothing is ever sent to the developer or any third party.

## Account integration note

The claude.ai usage data comes from an **unofficial, undocumented** endpoint — the
same one the Usage page uses, accessed with your own login. Logging in is entirely
optional; the app is fully functional without it. See the project README for the
Terms-of-Service note.

## Data sale, advertising, children

UsageMeter does not sell or share data (there is none to sell), shows no ads, and is
not directed at children. The "App Privacy" label on the Mac App Store is **"Data Not
Collected."**

## Changes & contact

Material changes will be posted to this page. Questions or concerns:
[github.com/OmerYasirOnal/UsageMeter/issues](https://github.com/OmerYasirOnal/UsageMeter/issues).

---

*UsageMeter is an independent project, not affiliated with, endorsed by, or
sponsored by Anthropic. "Claude" is a trademark of Anthropic PBC, used here only
to describe what the app tracks.*
