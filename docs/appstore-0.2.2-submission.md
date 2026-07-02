# App Store 0.2.2 submission — ready-to-go (verdict-day checklist)

State as of 2026-07-02: version **0.2.0 is WAITING_FOR_REVIEW** (since Jul 1).
Decision: let it ride — pulling it resets the queue and risks metadata mismatch.
Build **0.2.2 (5)** is already uploaded to App Store Connect and processing.

## When 0.2.0 is APPROVED (or rejected)

1. App Store Connect ▸ UsageMeter ▸ **"+" new version `0.2.2`**.
2. Attach build **5** (0.2.2, uploaded 2026-07-02, local-only `APPSTORE` variant).
3. Paste the "What's New" text below.
4. Replace the screenshots with the Kiln set (`docs/screenshots/` after the
   recapture — popover + dashboard, light).
5. Submit. (If 0.2.0 was REJECTED: fix per the rejection, then submit 0.2.2
   directly instead — same build, same notes.)

## What's New in 0.2.2 (App Store copy)

```
A fresh look and smarter insights — still 100% private, still no account needed.

• New "Kiln" design: a warm terracotta-and-teal look, fully adaptive to Light and Dark (your theme now applies everywhere, including the menu-bar popover).
• Forecasts: "on pace for ~420M tokens / ≈ $560 today," learned from your own daily rhythm — plus hover details, a 7-day trend line, and a week-over-week card on the dashboard.
• Weekly rhythm chart and month labels on the 12-month activity heatmap; heatmap shades now reflect your actual distribution of working days.
• Team snapshots: export a stats-only summary file and view your team's usage together — no server, nothing leaves your Mac except the file you choose to share.
• Rebuilt Settings with standard macOS tabs, plus a daily budget alert for your estimated API value.
• Faster: the active session log is parsed incrementally, and the local cache is about half the size.
```

## Feature-variant decisions (MVP policy, unchanged)

- App Store build stays **local-only** (`#if APPSTORE`): no claude.ai login, no
  unofficial endpoint, no update check (store handles updates). "Data Not
  Collected" privacy label remains true.
- Everything else ships in both variants (Kiln, forecasts, weekday rhythm,
  team snapshots, tabbed Settings, budget alerts) — all purely local.
