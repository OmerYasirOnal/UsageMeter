# Mac App Store — packaging roadmap

This is the plan to ship UsageMeter on the Mac App Store. The two hard parts are
the **App Sandbox** (mandatory) and the **Source A (claude.ai login) review risk**.

---

## TL;DR — the one decision that shapes everything

**Will the App Store build include Source A (claude.ai login + the unofficial
usage endpoint)?**

- **Option A — Local-only App Store build (recommended for a clean first approval).**
  Ship Claude Code stats (Source B) + service status (Source C) only. No login, no
  third-party endpoint → no ToS/review risk. Keep the full A+B+C build on GitHub /
  direct download. Fastest path to "Available on the App Store".
- **Option B — Full build with Source A.** Submit everything; be ready for a possible
  rejection under App Review guidelines (see Phase 5). Higher risk, more iteration.

Everything below assumes you do the sandbox work either way (required for both).

---

## Prerequisites

- **Apple Developer Program** membership — **$99/year** (individual or org).
- **App Store Connect** access; an **App ID / bundle identifier** you own
  (e.g. `com.omeryasironal.usagemeter`).
- **Xcode 26** (you have it). Signing certificates are created automatically by Xcode
  ("Automatically manage signing") once you're in the Developer Program.

---

## Phase 1 — Sandbox the app (the real engineering, ~1 day)

Mac App Store apps **must** run in the App Sandbox. Audit each feature:

| Feature | Sandbox status | Action |
|---|---|---|
| Write caches to Application Support | ✅ Works — resolves to the app **container** automatically (`~/Library/Containers/<id>/Data/...`). No code change. | none |
| Service status fetch (Source C) | ⚠️ Needs network entitlement | add `com.apple.security.network.client` |
| claude.ai login + replay (Source A) | ⚠️ Needs network entitlement | same as above |
| Launch at login (`SMAppService`) | ✅ Works in sandbox | none |
| Notifications (`UserNotifications`) | ✅ Works in sandbox | none |
| **Read `~/.claude/projects` (Source B)** | ❌ **Blocked** — outside the container | **security-scoped bookmark flow (below)** |

### The `~/.claude` access problem (the main code change)

A sandboxed app cannot read `~/.claude/projects` directly. The fix:

1. Add a **"Grant access to your Claude folder"** button in Settings that opens an
   `NSOpenPanel` (`canChooseDirectories = true`, `showsHiddenFiles = true`, default
   directory `~/.claude`). The user selects the folder once.
2. Save a **security-scoped bookmark** (`url.bookmarkData(options: .withSecurityScope)`)
   in a small `BookmarkStore`.
3. Before each scan, resolve the bookmark, call
   `startAccessingSecurityScopedResource()`, scan, then `stopAccessing…()`.
4. Empty-state copy: "Grant access to `~/.claude` to see your Claude Code stats."

**Entitlements** (`UsageMeter.entitlements`):

```xml
<key>com.apple.security.app-sandbox</key>                         <true/>
<key>com.apple.security.network.client</key>                      <true/>
<key>com.apple.security.files.user-selected.read-only</key>       <true/>
<key>com.apple.security.files.bookmarks.app-scope</key>           <true/>
```

**Status: ✅ implemented** in `ClaudeFolderAccess.swift` (resolve/restore/request a
security-scoped bookmark to `~/.claude`), wired into `AppModel` (the granted root is
merged into the engine config) and Settings ("Grant access to ~/.claude…"). It's
**additive**: the non-sandboxed build still reads `~/.claude/projects` directly, so
nothing changes there; the grant only matters once the app is sandboxed.
Remaining for the App Store target: add `UsageMeter.entitlements` (provided at the
repo root) to the Xcode app target's Signing & Capabilities.

> If you choose **Option A (local-only App Store build)**, you also gate out the
> account login UI behind a compile flag (e.g. `#if APPSTORE`) so the submitted
> binary has no claude.ai login at all.

---

## Phase 2 — Make it archivable in Xcode (~half day)

`Scripts/make_app.sh` hand-assembly can't produce an App Store package. You need an
Xcode **App target** that can be archived:

1. In Xcode: **File ▸ New ▸ Project ▸ macOS App** (SwiftUI). Bundle id =
   `com.omeryasironal.usagemeter`, deployment target **macOS 15**.
2. **Add the local package**: File ▸ Add Package Dependencies ▸ Add Local… → select
   this repo → add the `UsageMeterKit` library to the app target.
3. Move/`Add Files` the `Sources/UsageMeter/**` Swift files into the app target.
4. Target settings: `LSUIElement = YES` (Info.plist), **Signing & Capabilities ▸
   + App Sandbox** (and toggle Network/User-Selected-File as above), select your Team
   ("Automatically manage signing").
5. Build & run to confirm everything works **inside the sandbox** (this is where the
   `~/.claude` bookmark flow gets exercised).

> Keep SwiftPM (`make test`) as the source of truth for the engine + CI; the Xcode
> project is only the App Store shell. Commit the `.xcodeproj` (or a `project.yml`
> for XcodeGen) so it's reproducible.

---

## Phase 3 — App Store Connect setup + privacy label (~half day)

In **App Store Connect ▸ My Apps ▸ +**:

- **Name** "UsageMeter" (check availability), **Category** Developer Tools (or
  Utilities), **Price** Free.
- **Privacy Policy URL** (required) — host one (GitHub Pages off this repo works).
- **App Privacy "nutrition label"** — declare **"Data Not Collected"**. UsageMeter
  collects/transmits nothing, which is a genuine, strong selling point.
- **Screenshots** (use `make demo` for PII-free shots), **description**, **keywords**,
  **support URL** (the GitHub repo / issues).

---

## Phase 4 — Archive, upload, submit (~1 hour)

1. Xcode ▸ **Product ▸ Archive**.
2. Organizer ▸ **Distribute App ▸ App Store Connect ▸ Upload** (Xcode signs with the
   Mac App Distribution cert and uploads; no manual notarization needed for the App
   Store channel).
3. In App Store Connect, attach the build to the version, fill metadata, **Submit for
   Review**.

---

## Phase 5 — Review prep & likely rejections

**If you include Source A**, the realistic risks and responses:

- **Guideline 5.2.x (third-party rights / unauthorized use):** logging in to claude.ai
  and reading an undocumented endpoint may be flagged. **Response:** it accesses *the
  user's own account and own data* via their own login (like a browser), stores only
  session cookies, sends nothing anywhere. Provide the privacy policy. Be honest that
  if Apple insists, you'll ship Option A.
- **Guideline 4.0 / 2.5.1 (private APIs):** you use only public APIs — no issue; the
  concern is policy, not API. State this if asked.
- **WKWebView third-party sign-in:** generally allowed, but keep the flow obviously
  the official claude.ai page and never store credentials.

**If you ship Option A (local-only):** essentially no third-party-service risk — a
local developer utility that reads local files (with user-granted access) and a public
status page. Smooth approval expected.

General: a menu-bar-only (`LSUIElement`) app is allowed; just make sure there's a
clear way to reach settings/quit (there is, via the popover).

---

## Effort & cost summary

| Item | Cost / effort |
|---|---|
| Apple Developer Program | **$99 / year** |
| Sandbox + bookmark flow (code) | ~1 day |
| Xcode app target + signing | ~0.5 day |
| App Store Connect metadata + privacy + screenshots | ~0.5 day |
| Review iteration | variable (days–weeks if Source A is challenged) |

## Recommendation

1. Do the **sandbox + bookmark** work (needed regardless) and keep `make test` green.
2. Ship **Option A (local-only)** to the App Store first for a clean, fast approval —
   "Claude Code usage + status, 100% private, no account needed."
3. Keep the **full A+B+C** build on GitHub Releases (already live) for users who want
   the live session/weekly %.
4. Optionally, later, try submitting the full build (Option B) once the local-only app
   is established and you have a privacy policy + review history.
