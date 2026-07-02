# App Store 0.2.1 UX Package Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix the three review-confirmed UX gaps in the local-only App Store build: (1) notifications are dead code (account-gated), (2) the first-run empty state is a dead end (no path to the sandbox grant), (3) account-dependent Settings/privacy copy ships un-gated. Plus one adjacent default: the APPSTORE menu bar shows a useful number out of the box.

**Architecture:** The only new logic is `DailyBudgetPolicy` — a pure, tested Kit type (mirrors `NotificationPolicy`) that alerts once per local-calendar day when today's Source-B "API value" crosses a user-set budget. It works with **no account**, so notifications become functional in the App Store build and for logged-out GitHub users. Everything else is SwiftUI gating (`#if APPSTORE`) and a build-specific default. State persistence reuses `MetricAlertState` (keyed `"Daily budget"`, `cycleKey = dayKey`) so `UsageNotifier`'s store format doesn't change.

**Tech Stack:** Swift 6, swift-testing, SwiftPM. Kit changes are TDD'd; app-target changes are compile-verified in BOTH variants (`swift build` and `swift build -Xswiftc -DAPPSTORE`).

## Global Constraints

- Do NOT bump version/build numbers — 0.2.0 is `WAITING_FOR_REVIEW`; 0.2.1 numbering happens at submission time.
- Demo mode must not fire notifications (already true: `AppModel.refresh()`'s demo path returns before `notifier.evaluate`; keep it that way).
- `UserDefaults` decode compatibility: `notifier.metricStates.v1` blob format unchanged (that's why `MetricAlertState` is reused, not extended).
- Budget semantics: `dailyBudgetUSD <= 0` means OFF. Alert fires at most once per local-calendar day.
- Work on branch `feat/appstore-021-ux`; merge to `main` at the end.

---

### Task 0: Branch

- [ ] `git checkout -b feat/appstore-021-ux`

---

### Task 1: Kit — `DailyBudgetPolicy` (+ `UsageAlertKind.budget`)

**Files:**
- Modify: `Sources/UsageMeterKit/Engine/NotificationPolicy.swift`
- Test: `Tests/UsageMeterKitTests/NotificationPolicyTests.swift`

**Interfaces:**
- Produces: `UsageAlertKind.budget` (new enum case; `UsageAlert.id` → `"\(metric)-budget"`). `DailyBudgetPolicy.metricName == "Daily budget"`. `DailyBudgetPolicy.evaluate(todayCost: Double?, budgetUSD: Double?, dayKey: String, prior: MetricAlertState?) -> (alerts: [UsageAlert], state: MetricAlertState)`.

- [ ] **Step 1.1: Failing tests** — append a new suite to `Tests/UsageMeterKitTests/NotificationPolicyTests.swift`:

```swift
@Suite struct DailyBudgetPolicyTests {
    @Test func firesOncePerDayWhenBudgetCrossed() {
        let first = DailyBudgetPolicy.evaluate(todayCost: 12.5, budgetUSD: 10, dayKey: "2026-7-2", prior: nil)
        #expect(first.alerts.count == 1)
        #expect(first.alerts.first?.kind == .budget)

        // Same day, still over budget → no repeat.
        let second = DailyBudgetPolicy.evaluate(todayCost: 15.0, budgetUSD: 10, dayKey: "2026-7-2", prior: first.state)
        #expect(second.alerts.isEmpty)
    }

    @Test func reArmsOnANewDay() {
        let fired = DailyBudgetPolicy.evaluate(todayCost: 12.5, budgetUSD: 10, dayKey: "2026-7-2", prior: nil)
        let nextDay = DailyBudgetPolicy.evaluate(todayCost: 11.0, budgetUSD: 10, dayKey: "2026-7-3", prior: fired.state)
        #expect(nextDay.alerts.count == 1)
    }

    @Test func silentWhenOffBelowOrUnknown() {
        #expect(DailyBudgetPolicy.evaluate(todayCost: 99, budgetUSD: 0, dayKey: "d", prior: nil).alerts.isEmpty)   // off
        #expect(DailyBudgetPolicy.evaluate(todayCost: 99, budgetUSD: nil, dayKey: "d", prior: nil).alerts.isEmpty) // off
        #expect(DailyBudgetPolicy.evaluate(todayCost: 5, budgetUSD: 10, dayKey: "d", prior: nil).alerts.isEmpty)   // below
        #expect(DailyBudgetPolicy.evaluate(todayCost: nil, budgetUSD: 10, dayKey: "d", prior: nil).alerts.isEmpty) // unknown cost
    }

    @Test func exactBudgetCountsAsCrossed() {
        let r = DailyBudgetPolicy.evaluate(todayCost: 10, budgetUSD: 10, dayKey: "d", prior: nil)
        #expect(r.alerts.count == 1)
    }
}
```

- [ ] **Step 1.2:** `swift test --filter DailyBudgetPolicyTests` → compile error (type missing) = red.
- [ ] **Step 1.3: Implement** in `NotificationPolicy.swift`: add `case budget` to `UsageAlertKind`, `case .budget: return "\(metric)-budget"` to `UsageAlert.id`, and append:

```swift
/// Pure decision logic for the local (Source B) daily-budget alert. Needs no
/// account, so notifications stay useful in the local-only App Store build and
/// for logged-out users. Reuses `MetricAlertState` (cycleKey = local day key;
/// `firedBurnRate` doubles as the "fired today" flag) so the notifier's
/// persisted state format is unchanged.
public enum DailyBudgetPolicy {
    public static let metricName = "Daily budget"

    public static func evaluate(
        todayCost: Double?,
        budgetUSD: Double?,
        dayKey: String,
        prior: MetricAlertState?
    ) -> (alerts: [UsageAlert], state: MetricAlertState) {
        var state = prior ?? MetricAlertState(cycleKey: dayKey)
        if state.cycleKey != dayKey {
            state = MetricAlertState(cycleKey: dayKey)   // new day → re-arm
        }
        guard let budgetUSD, budgetUSD > 0,
              let todayCost, todayCost >= budgetUSD,
              !state.firedBurnRate else {
            return ([], state)
        }
        state.firedBurnRate = true
        let alert = UsageAlert(
            metric: metricName, kind: .budget,
            title: "Daily budget reached",
            body: String(format: "Today's Claude Code API value (≈ $%.2f) crossed your $%.2f daily budget.", todayCost, budgetUSD))
        return ([alert], state)
    }
}
```

- [ ] **Step 1.4:** `swift test` → all green.
- [ ] **Step 1.5:** Commit: `git add Sources/UsageMeterKit/Engine/NotificationPolicy.swift Tests/UsageMeterKitTests/NotificationPolicyTests.swift && git commit -m "Kit: DailyBudgetPolicy — local Source-B budget alert (once per day)"`

---

### Task 2: App — settings field + notifier wiring

**Files:**
- Modify: `Sources/UsageMeter/App/AppSettings.swift` (new `dailyBudgetUSD`; APPSTORE-default for `showCostInMenuBar`)
- Modify: `Sources/UsageMeter/App/UsageNotifier.swift` (evaluate signature + budget path)
- Modify: `Sources/UsageMeter/App/AppModel.swift` (call site)

**Interfaces:**
- Produces: `AppSettings.dailyBudgetUSD: Double` (default 0 = off; key `settings.dailyBudgetUSD`, object-check load pattern). `UsageNotifier.evaluate(_ account: AccountUsage?, todayCost: Double?, dailyBudgetUSD: Double, enabled: Bool, now: Date = Date())`.

- [ ] **Step 2.1: `AppSettings`** — add `var dailyBudgetUSD: Double` after `notificationsEnabled`; in `default` use `dailyBudgetUSD: 0`; replace the plain-bool default for `showCostInMenuBar` with a build-specific one:

```swift
    static let `default` = AppSettings(
        projectRootPaths: [],
        refreshIntervalMinutes: 1,
        launchAtLogin: false,
        showCostInMenuBar: defaultShowCostInMenuBar,
        showPercentInMenuBar: true,
        showApiValue: true,
        notificationsEnabled: true,
        dailyBudgetUSD: 0,
        appearance: .system,
        showSampleData: false
    )

    /// The App Store build has no account %, so the menu bar would show a bare
    /// glyph by default; start with today's API value visible there instead.
    private static var defaultShowCostInMenuBar: Bool {
        #if APPSTORE
        true
        #else
        false
        #endif
    }
```

Persistence: `static let dailyBudget = "settings.dailyBudgetUSD"` in `Keys`; in `load()` use the object-check pattern for BOTH `dailyBudgetUSD` and (now) `showCostInMenuBar` (a missing key must keep the build-specific default, not read `false`); in `save()` add `defaults.set(dailyBudgetUSD, forKey: Keys.dailyBudget)`.

- [ ] **Step 2.2: `UsageNotifier.evaluate`** — restructure so the account is optional and the budget path always runs:

```swift
    /// Evaluate the latest snapshot data and fire any due notifications.
    /// Account metrics need Source A; the daily-budget alert works from local
    /// Source-B data alone (incl. the local-only App Store build).
    func evaluate(_ account: AccountUsage?, todayCost: Double?, dailyBudgetUSD: Double,
                  enabled: Bool, now: Date = Date()) {
        guard enabled, isAvailable, authorized else { return }
        var toFire: [UsageAlert] = []
        if let account {
            let metrics: [(String, UsageMetric?)] = [
                ("Session", account.session),
                ("Weekly", account.weekly),
                ("Weekly Opus", account.weeklyOpus)
            ]
            for (name, metric) in metrics {
                guard let metric else { continue }
                let result = NotificationPolicy.evaluate(
                    metricName: name, percent: metric.percent, resetsAt: metric.resetsAt,
                    now: now, prior: states[name])
                states[name] = result.state
                toFire.append(contentsOf: result.alerts)
            }
        }
        let budgetResult = DailyBudgetPolicy.evaluate(
            todayCost: todayCost, budgetUSD: dailyBudgetUSD,
            dayKey: Self.dayKey(for: now), prior: states[DailyBudgetPolicy.metricName])
        states[DailyBudgetPolicy.metricName] = budgetResult.state
        toFire.append(contentsOf: budgetResult.alerts)
        save()
        toFire.forEach(post)
    }

    /// Local-calendar day key (what a user means by "today").
    private static func dayKey(for date: Date) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return "\(c.year ?? 0)-\(c.month ?? 0)-\(c.day ?? 0)"
    }
```

- [ ] **Step 2.3: `AppModel.refresh()`** call site becomes:

```swift
            notifier.evaluate(snapshot.account,
                              todayCost: snapshot.claudeCode.todayEstimatedCost,
                              dailyBudgetUSD: settings.dailyBudgetUSD,
                              enabled: settings.notificationsEnabled)
```

- [ ] **Step 2.4:** `swift build && swift test` → green. Commit: `git commit -m "Daily budget alert wired: settings field + notifier evaluates Source-B cost"`

---

### Task 3: Popover empty state — grant CTA + scanning state

**Files:**
- Modify: `Sources/UsageMeter/MenuBar/MenuBarContentView.swift`

- [ ] **Step 3.1:** Add state to the view: `@State private var folderGranted = ClaudeFolderAccess.isGranted`, refreshed in `.onAppear`. Replace the `cc.recordCount == 0` branch body with `emptyState`, and add:

```swift
    /// First-run guidance. Ordered: still scanning → (App Store) missing sandbox
    /// grant → genuinely no usage. The grant CTA is the fix for the "empty app
    /// with no path forward" dead end in the sandboxed build.
    @ViewBuilder
    private var emptyState: some View {
        if !model.hasLoadedOnce {
            Text("Scanning session logs…")
                .font(.caption2).foregroundStyle(.secondary)
        } else {
            #if APPSTORE
            if !folderGranted {
                VStack(alignment: .leading, spacing: 6) {
                    Text("UsageMeter needs permission to read your Claude Code session logs (token counts only — never messages).")
                        .font(.caption2).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Button {
                        Task {
                            await model.grantClaudeFolderAccess()
                            folderGranted = ClaudeFolderAccess.isGranted
                        }
                    } label: {
                        Label("Grant access to ~/.claude…", systemImage: "folder.badge.plus")
                    }
                }
            } else {
                noUsageYet
            }
            #else
            noUsageYet
            #endif
        }
    }

    private var noUsageYet: some View {
        Text("No Claude Code usage yet. Run Claude Code, then refresh.")
            .font(.caption2).foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
```

- [ ] **Step 3.2:** `swift build && swift build -Xswiftc -DAPPSTORE` → both compile. Commit: `git commit -m "Popover empty state: sandbox grant CTA + scanning state (App Store first-run)"`

---

### Task 4: Settings gating + notification copy

**Files:**
- Modify: `Sources/UsageMeter/Settings/SettingsView.swift`

- [ ] **Step 4.1: General section** — wrap the dead toggle and trim the caption:

```swift
                #if !APPSTORE
                Toggle("Show account session % in the menu bar", isOn: $model.settings.showPercentInMenuBar)
                #endif
                Toggle("Show today's API value in the menu bar", isOn: $model.settings.showCostInMenuBar)
                Toggle("Show Claude Code \u{201C}API value\u{201D} estimate", isOn: $model.settings.showApiValue)
                #if APPSTORE
                Text("\u{201C}API value\u{201D} is what your local Claude Code tokens would cost on the pay-as-you-go API — i.e. the value you get from your subscription, not money you spent.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                #else
                Text("\u{201C}API value\u{201D} is what your local Claude Code tokens would cost on the pay-as-you-go API — i.e. the value you get from your subscription, not money you spent. Your real pay-as-you-go spend is read from claude.ai and shown under Account.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                #endif
```

- [ ] **Step 4.2: Notifications section** — per-build caption + budget field:

```swift
            Section("Notifications") {
                Toggle("Alert me near my limits", isOn: $model.settings.notificationsEnabled)
                #if APPSTORE
                Text("Notifies you when today's Claude Code API value crosses your daily budget. (Requires notification permission.)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                #else
                Text("Notifies you at 50%, 75% and 90% of your session/weekly limit, when your current pace is on track to hit a limit before it resets, and when today's API value crosses your daily budget. (Account alerts require logging in; all alerts require notification permission.)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                #endif
                HStack {
                    Text("Daily API-value budget")
                    Spacer()
                    TextField("$0", value: $model.settings.dailyBudgetUSD,
                              format: .currency(code: "USD").precision(.fractionLength(0...2)))
                        .frame(width: 90)
                        .multilineTextAlignment(.trailing)
                        .disabled(!model.settings.notificationsEnabled)
                }
                Text("Alerts once per day when today's estimated API value crosses this amount. Set to $0 to turn it off.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
```

- [ ] **Step 4.3: Privacy section** — gate the Source-A line:

```swift
                #if !APPSTORE
                Label("Account (Source A): UsageMeter reads only your usage percentages and reset times from claude.ai — never conversation content. Only your login session is stored locally, and Log out wipes it.",
                      systemImage: "lock.shield")
                    .font(.caption)
                #endif
```

- [ ] **Step 4.4:** `swift build && swift build -Xswiftc -DAPPSTORE && swift test` → green. Commit: `git commit -m "Gate account-dependent Settings/privacy copy out of the App Store build"`

---

### Task 5: Verify both variants, docs, merge

- [ ] **Step 5.1:** `make test` (full) + `swift build -Xswiftc -DAPPSTORE` one last time. If the SwiftPM `-DAPPSTORE` build fails for PRE-EXISTING reasons (files not designed for SwiftPM+APPSTORE), verify via `xcodebuild -project UsageMeter.xcodeproj -scheme UsageMeterApp build` instead and note it.
- [ ] **Step 5.2:** `docs/STATUS.md`: add a "What's done" bullet — App Store 0.2.1 UX package ready (grant CTA, gated copy, local daily-budget notifications, APPSTORE menu-bar default); note it ships as 0.2.1 after Apple's 0.2.0 verdict.
- [ ] **Step 5.3:** Merge & push:

```bash
git checkout main
git merge --no-ff feat/appstore-021-ux -m "App Store 0.2.1 UX package: grant CTA, gated copy, local budget alerts"
swift test && git push origin main && git push origin feat/appstore-021-ux
```

## Self-Review Notes

- Finding 1 scope check: full threshold parity (50/75/90 of *limits*) is impossible from Source B (no local limit data); the budget alert is the honest local equivalent and was the review's own suggestion. Metric picker for the menu bar stays deferred.
- `MetricAlertState.firedBurnRate` reuse is documented at the definition site of `DailyBudgetPolicy`; the `"Daily budget"` key can't collide with account metric names.
- `showCostInMenuBar` load-pattern change is required or the APPSTORE default would be silently overridden to `false` by the missing key.
