# Contributing to UsageMeter

Thanks for your interest! UsageMeter is a native macOS menu-bar app (Swift 6 +
SwiftUI, SwiftPM, no Xcode project file).

## Ground rules

1. **Privacy is a hard rule.** Never read or persist conversation/message content.
   Source B reads only `type`, `isSidechain`, `requestId`/`uuid`, `timestamp`,
   `message.model`, and `message.usage.*`. Source A reads only usage numbers, reset
   times, and the user's own spend. The login capture must only ever touch
   usage-shaped, first-party responses.
2. **Keep the three sources decoupled** (behind `ClaudeCodeSource`, `StatusClient`,
   `AccountUsageClient`). The app must stay useful with any subset available.
3. **Decode defensively** — no force-unwraps on decoded JSON; handle not-logged-in,
   endpoint-changed, offline, and malformed input as graceful states.

## Workflow

```bash
make test    # run the headless test suite (must stay green)
make run     # build + launch the app
make app     # assemble UsageMeter.app
```

- Put logic in `Sources/UsageMeterKit/` (the headless, testable engine) and keep
  `Sources/UsageMeter/` a thin SwiftUI shell.
- Add/adjust tests in `Tests/UsageMeterKitTests/` for any engine change. Tests use
  fixtures/mocks — no live network or real user data.
- Match the surrounding code style; the design system lives in `Theme.swift`.

## Source-A note

The claude.ai usage endpoint is unofficial and undocumented (a ToS grey area). Keep
all of it isolated behind `AccountUsageClient` / `AccountUsageDecoder` so changes are
contained to one place.

## Reporting issues

Please include macOS version, how you installed the app, and steps to reproduce.
Never paste conversation content or session cookies into issues.
