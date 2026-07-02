# Kiln Design Direction + Usability Foundation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans. UI-only work (app target has no test suite) — every task is verified by `swift build` (both variants) and the batch ends with real-app light/dark screenshot verification.

**Goal:** Apply the "Kiln" duotone identity (teal interactive chrome + terracotta data ink) and the direction-independent usability foundation from the 2026-07-02 design review: adaptive light/dark tokens that pass contrast, color-as-state, popover de-duplication and hierarchy, keyboard shortcuts, native card/material treatment, quick wins, and a re-colored app icon.

**Architecture:** All color decisions flow through `Theme.swift` (rewritten with a `Color(light:dark:)` dynamic-appearance init and hex tokens). Call sites are re-classified chrome (`Theme.accent`, teal) vs data (`Theme.data`, terracotta). Kit (`UsageMeterKit`) is untouched except nothing — pure app-target work.

## Global Constraints

- Kiln tokens (light/dark): accent #0F766E/#2DD4BF; accentSoft #DDF0ED/#11332F; data #C2410C/#FB923C; ok #277E42/#4ADE80; warning #96690B/#FBBF24; warningSoft #F6EDD4/#3A2E0F; danger #B91C1C/#F87171; maintenance #3B6EA8/#7FB0E8; chart gradient #E58F5E→#C2410C / #FDAF74→#EA7A33; heatmap opaque stops #F6E0D2/#ECB088/#D0784A/#A93E0F (light), #3E2415/#6E3D1E/#B45E2C/#FB923C (dark); empty/quota-track = `NSColor.quaternarySystemFill`.
- Color-as-state: big % numerals `.primary` below 75, warning 75–90, danger 90+; menu-bar icon `.primary` unless session ≥75 or a status incident.
- Both build variants must compile (`swift build`, `swift build -Xswiftc -DAPPSTORE`); 144 kit tests stay green.
- Verify visually on the REAL app (make install + screencapture) in light AND dark before merging; README screenshots re-captured.
- Branch `feat/kiln-design`; merge to main at the end.

## Tasks

1. **Theme rewrite** — `Color(light:dark:)` + full Kiln token set + `numeralColor(_:)` + chart/heat tokens + adaptive `CardBackground` (quaternarySystemFill + separator hairline) + UsageBar threshold ticks at 75/90 + Reduce Motion in UsageBar. Verify: build.
2. **Semantic unification** — StatusIndicator colors through Theme; SettingsView `.green` → `Theme.ok`; insight icons → `.secondary`; spend numeral → `.primary` 32pt.
3. **Color-as-state call sites** — numerals via `Theme.numeralColor`; MenuBarLabel tint logic (primary unless ≥75/incident, compact `menuBarCost`, monospaced); chart gradient; byModel bars → `Theme.data`; ActivityGrid opaque ramp + `heatEmpty`; shareable card → data ink; icon glyphs.
4. **Popover restructure** — session hero (30pt % + right-aligned big countdown), Weekly/Opus compact rows (projection only on `.exhausts`), 5h block hidden when session metric exists, spend row hidden when 0, status → header dot (text row only during incidents), API-value disclaimer → info-glyph `.help`, privacy footer removed, header de-duped (chart icon out, footer Dashboard stays), hover state on icon buttons + a11y labels, ⌘R/⌘,/⌘D/⌘Q/Esc shortcuts, block label shortened, reduced-motion gating on contentTransition.
5. **Formatting quick wins** — `cost()` forced en_US USD; `menuBarCost()`; `weekdayTime` localized template ("EEEjmm"); `axisTokens()` (no trailing .0) wired into the chart; dashboard content max width 880.
6. **Icon regeneration** — `Scripts/icon/render.swift` terracotta trio (#F29E54 / #C2410C / #7C2D0C), `make icon`.
7. **Verification & ship** — builds + tests; `make install`; real screenshots light+dark popover/dashboard; compare with old; update README screenshots; docs (STATUS/CLAUDE); merge + push.

(Complete code lives in the implementation commits; this plan records scope, tokens, and verification gates.)
