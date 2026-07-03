# App Store — Review Notes & Demo Script

Resubmit-ready assets to reduce App Review friction for the **local-only
`APPSTORE` build**. **Do not edit the currently in-review 1.0.0 (build 7)
submission** — pulling it resets the queue and reopens the 2.3.1 metadata-mismatch
risk. Use this only when preparing a resubmit (after a rejection) or the next
version.

The single most likely rejection for this app is **2.1 (a reviewer opens it on a
Mac with no Claude Code history and sees an empty app)** and **confusion about what
it does / whether an account is needed**. The notes below pre-empt both; the demo
recording removes the empty-state problem entirely.

---

## 1. Notes for Reviewer (paste into ASC → App Review Information → Notes)

```
UsageMeter is a menu-bar utility that shows your own Claude Code usage
(token counts, estimated API-rate value, per-model/per-project breakdowns)
read from local log files on this Mac. No account, no login, and no network
sign-in are required for this build.

HOW TO SEE A POPULATED APP (no real data needed):
1. Launch the app — its icon appears in the macOS menu bar (top-right). It has
   no Dock icon and no main window; click the menu-bar icon to open it.
2. Open Settings from the menu-bar popover (gear icon), and turn ON
   "Show sample data (preview)". The popover and Dashboard immediately fill
   with synthetic example usage so you can review every screen without any
   real Claude Code history on the test device.

ABOUT THE FOLDER-ACCESS PROMPT:
On first real use the app asks you to grant read access to your "~/.claude"
folder (a standard sandbox NSOpenPanel, "Grant Access"). This is only so it can
read Claude Code's local usage logs. It is optional for review — the
"Show sample data" toggle needs no folder access.

PRIVACY:
The app reads only token counts, model names, and timestamps — never message
or conversation content. Nothing is sent anywhere; there is no server, no
telemetry, no analytics. App Privacy is correctly declared "Data Not Collected."

UsageMeter is an independent project, not affiliated with or endorsed by
Anthropic. "Claude" is used only descriptively to name what the app tracks.

A ~25-second demo screen recording is attached / available at:
<PASTE UNLISTED VIDEO LINK OR NOTE "attached as App Preview">
```

Keep it plain text (ASC strips formatting). Update the video link line before
submitting.

---

## 2. Demo screen-recording scenario (~25 s)

Purpose: a short, PII-free walkthrough that shows the app **populated**, so the
reviewer never has to reproduce data themselves. Record on a clean macOS install
or a fresh user account for a tidy menu bar.

Setup (PII-free data):
- Run the store build with sample data on. Either flip **Settings → "Show sample
  data (preview)"**, or launch with the env var: `USAGEMETER_DEMO=1`.
- Use the Kiln appearance the listing screenshots use (default).
- Hide personal menu-bar items / use a clean account so nothing identifying is
  in frame.

Shot list:
1. **(0–4 s)** Menu bar at rest → click the UsageMeter icon. The popover opens
   showing the session hero, weekly limit, reset countdown, and today's Claude
   Code tokens + API value.
2. **(4–10 s)** Point out (cursor move) the "Claude Code — Today" and 5-hour
   block rows — the local-log data this build is about.
3. **(10–18 s)** Click **Open Dashboard**. Show the usage-history chart, the
   12-month activity heatmap, and by-model / by-project.
4. **(18–23 s)** Open **Settings**, show **"Show sample data (preview)"** toggle
   and the **appearance** options; briefly show the privacy line ("never reads
   your messages").
5. **(23–25 s)** Back to the menu bar; quit from the popover. End.

Keep it silent or add one calm caption per shot. Export at the display's native
resolution; trim dead frames. Attach as an **App Preview** (per-localization,
specific pixel sizes required) OR host unlisted (e.g. YouTube unlisted) and put
the link in the review notes above — the link is lower-friction and never blocks
submission on video encoding specs.

---

## 3. Pre-resubmit checklist

- [ ] Screenshots are **local-only** (Claude Code / Dashboard, no account %). Never
      show session/weekly-account imagery — that is the 2.3.1 trigger that killed
      the original full build.
- [ ] Keywords contain **no** `anthropic` (or any other company trademark). See
      `APP_STORE_LISTING.md`.
- [ ] Description carries the "not affiliated with Anthropic" disclaimer.
- [ ] App Privacy = "Data Not Collected"; `ITSAppUsesNonExemptEncryption = NO`.
- [ ] Notes for Reviewer (section 1) pasted, video link filled in.
- [ ] Build is the `APPSTORE` variant (`SWIFT_ACTIVE_COMPILATION_CONDITIONS: APPSTORE`)
      — no `#if !APPSTORE` account/login UI compiled in.
