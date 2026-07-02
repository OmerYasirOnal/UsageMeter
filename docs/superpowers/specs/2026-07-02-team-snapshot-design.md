# Team snapshot (Stage 0, serverless) — design

**Date:** 2026-07-02. Chosen over a backend for the first team/admin step: each
member exports a **stats-only** summary file; the admin imports those files into
a Team section on the dashboard. No server, no accounts — the local-only privacy
promise stays intact ("only the file YOU choose to send"). Also validates the
data model for a future Stage 1 backend.

## File format — `.umteam` (JSON, versioned)

```json
{
  "schemaVersion": 1,
  "member": "Ömer Yasir Önal",        // NSFullUserName() at export
  "generatedAt": "2026-07-02T12:00:00Z",
  "days": 90,                          // window covered by byDay
  "totalTokens": 8446300000,
  "totalCost": 6268.44,                // null when unknown
  "sessionCount": 95,
  "byModel": [{"family": "opus", "tokens": 7722900000, "cost": 5231.08}],
  "byDay": [{"day": "2026-07-01", "tokens": 349100000, "cost": 458.69}]
}
```

**Privacy rule:** NO project entries — project slugs encode absolute paths and
macOS usernames; a team file must not leak a member's directory layout. No
message-adjacent data exists anywhere upstream anyway.

## Kit (`Sources/UsageMeterKit/Team/TeamSummary.swift`, TDD)

- `TeamSummary` Codable model + `make(from stats: ClaudeCodeStats, member:, now:, days: 90)`
  (last-90-days byDay slice; byModel collapsed to family/tokens/cost).
- `encode() -> Data` (pretty, sorted keys) / `decode(Data) -> TeamSummary?`
  (nil on wrong/missing schemaVersion or garbage — fail safe).
- `TeamMemberRow` compute: tokens (window), cost, weekOverWeekChange (reuse the
  same complete-days semantics), lastActiveDay — pure, from a `TeamSummary` +
  `now`/`calendar`.

## App

- **Export**: Dashboard Export menu gains "Team summary (.umteam)…" →
  `NSSavePanel` (suggested name `Yasir-2026-07-02.umteam`). Uses
  `model.snapshot.claudeCode`.
- **Team card** on the dashboard (below By project): empty state = "Import your
  team's .umteam files" + **Add Files…** button (NSOpenPanel, multi-select) and
  drag-&-drop support. Populated = table (Member · Tokens · API value · 7-day Δ ·
  Last active) sorted by tokens, plus a compact per-member bar chart
  (`Theme.data`, member's own row uses full ink; imports include the admin's own
  file like anyone else's).
- **Persistence**: imported files are copied to
  `Application Support/UsageMeter/team/` and reloaded on launch; a row's context
  menu (and a ⌫ button) removes a member (deletes the copied file).
- Both build variants (file-picker based → sandbox-safe).

## Testing

Round-trip encode/decode; schemaVersion mismatch → nil; byDay slicing window;
member-row math (Δ, last active); a test asserting the encoded JSON contains no
"project" key (privacy lock, mirrors the UsageRecord approach).

## Out of scope

Signing/tamper-proofing, live sync, invites, roles, consent flows (all Stage 1,
which gets its own spec when we take it up).
