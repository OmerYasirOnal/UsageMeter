import SwiftUI
import AppKit
import UsageMeterKit

/// Tabbed settings, standard macOS anatomy. Each tab is its own focused Form;
/// the window (the `Settings` scene) hugs the active tab's content height.
struct SettingsView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        TabView {
            GeneralSettingsTab()
                .tabItem { Label("General", systemImage: "gearshape") }
            DataSettingsTab()
                .tabItem { Label("Data", systemImage: "folder") }
            NotificationSettingsTab()
                .tabItem { Label("Notifications", systemImage: "bell.badge") }
            #if !APPSTORE
            AccountSettingsTab()
                .tabItem { Label("Account", systemImage: "person.crop.circle") }
            #endif
            AboutSettingsTab()
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: 560)
        .fixedSize(horizontal: false, vertical: true)
        .tint(Theme.accent)
        .managesActivationPolicy()
    }
}

// MARK: - General

private struct GeneralSettingsTab: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Form {
            Section("Appearance") {
                Picker("Theme", selection: $model.settings.appearance) {
                    ForEach(AppAppearance.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                Text("Applies everywhere — popover, dashboard, and this window.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Menu bar") {
                // Account-dependent controls/copy are compiled out of the
                // local-only App Store build — there is no login there.
                #if !APPSTORE
                Toggle("Show account session % in the menu bar", isOn: $model.settings.showPercentInMenuBar)
                #endif
                Toggle("Show today's API value in the menu bar", isOn: $model.settings.showCostInMenuBar)
            }

            Section("Claude Code estimate") {
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
            }

            Section {
                Toggle("Launch at login", isOn: $model.settings.launchAtLogin)
                    .disabled(!LaunchAtLogin.isAvailable)
                if !LaunchAtLogin.isAvailable {
                    Text("Launch at login requires the bundled app (build with `make app`).")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Toggle("Show sample data (preview)", isOn: $model.settings.showSampleData)
                Text("Displays synthetic example usage so you can preview UsageMeter before you have Claude Code history.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Data (Source B folders + refresh)

private struct DataSettingsTab: View {
    @EnvironmentObject private var model: AppModel

    /// Raw editor text — the user types freely; we normalize into settings only on
    /// commit (Apply / focus loss / folder pick), never per keystroke. This avoids
    /// the lossy round-trip that resets the insertion point and the per-keystroke
    /// engine rescans.
    @State private var rootsText = ""
    @FocusState private var rootsFocused: Bool
    @State private var folderGranted = ClaudeFolderAccess.isGranted

    var body: some View {
        Form {
            Section("Claude Code logs (Source B)") {
                Text("Folders scanned for Claude Code session logs (one path per line). Leave empty to use the defaults (~/.claude/projects and the Xcode CodingAssistant path).")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                TextEditor(text: $rootsText)
                    .focused($rootsFocused)
                    .font(.system(.body, design: .monospaced))
                    .frame(minHeight: 64, maxHeight: 96)
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(.quaternary))
                    .onChange(of: rootsFocused) { _, focused in
                        if !focused { commitRoots() }
                    }

                HStack {
                    Button("Add Folder…") { chooseFolder() }
                    Button("Apply") { commitRoots() }
                    Button("Reset to Defaults") {
                        rootsText = ""
                        commitRoots()
                    }
                    Spacer()
                }

                HStack {
                    if folderGranted {
                        Label("Folder access granted", systemImage: "checkmark.seal.fill")
                            .foregroundStyle(Theme.ok).font(.caption)
                    } else {
                        Button("Grant access to ~/.claude…") {
                            Task { await model.grantClaudeFolderAccess(); folderGranted = ClaudeFolderAccess.isGranted }
                        }
                    }
                    Spacer()
                }
                Text("Only needed for the sandboxed / Mac App Store build — the direct-download build reads ~/.claude automatically.")
                    .font(.caption2).foregroundStyle(.secondary)
            }

            Section("Refresh") {
                Stepper(value: $model.settings.refreshIntervalMinutes, in: 1...60, step: 1) {
                    Text("Every \(Int(model.settings.refreshIntervalMinutes)) min")
                }
                Text("Source A and the status page are polled politely on top of this; the popover also refreshes on open.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear {
            rootsText = model.settings.projectRootPaths.joined(separator: "\n")
        }
        .onDisappear { commitRoots() }   // leaving the tab commits, like focus loss
    }

    /// Normalize the raw editor text into the settings array (only if changed).
    private func commitRoots() {
        let parsed = rootsText
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        if parsed != model.settings.projectRootPaths {
            model.settings.projectRootPaths = parsed
        }
    }

    private func chooseFolder() {
        // Accessory (LSUIElement) apps aren't frontmost; activate so the panel
        // comes to the front and takes key focus.
        NSApp.activate(ignoringOtherApps: true)
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        if panel.runModal() == .OK {
            var lines = rootsText.isEmpty ? [] : rootsText.components(separatedBy: "\n")
            lines.append(contentsOf: panel.urls.map { $0.path })
            rootsText = lines.joined(separator: "\n")
            commitRoots()
        }
    }
}

// MARK: - Notifications

private struct NotificationSettingsTab: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Form {
            Section("Alerts") {
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
            }

            Section("Daily budget") {
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
        }
        .formStyle(.grouped)
    }
}

// MARK: - Account (Source A) — compiled out of the local-only App Store build.

#if !APPSTORE
private struct AccountSettingsTab: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Form {
            Section("claude.ai (Source A)") {
                HStack {
                    if model.accountAuth.isAuthenticated {
                        Label("Signed in", systemImage: "checkmark.seal.fill")
                            .foregroundStyle(Theme.ok)
                        Spacer()
                        Button("Log out") { Task { await model.logOut() } }
                    } else {
                        Label("Not signed in (local-only mode)", systemImage: "lock.open")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Log in…") {
                            openWindow(id: AppWindowID.accountLogin)
                            NSApp.activate(ignoringOtherApps: true)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Theme.accent)
                    }
                }
                Text("Logging in to claude.ai uses an unofficial usage endpoint (a Terms-of-Service grey area). UsageMeter never sees your password — only session cookies are stored, and Log out wipes them. The app stays fully usable without logging in.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}
#endif

// MARK: - About

private struct AboutSettingsTab: View {
    @EnvironmentObject private var model: AppModel
    @State private var checking = false
    @State private var checkedOnce = false

    private var version: String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String
        switch (short, build) {
        case let (s?, b?): return "\(s) (\(b))"
        case let (s?, nil): return s
        default: return "dev build (swift run)"
        }
    }

    var body: some View {
        Form {
            Section("UsageMeter") {
                LabeledContent("Version", value: version)
                // App Store builds update through the store — no self-check there.
                #if !APPSTORE
                HStack {
                    if let update = model.availableUpdate {
                        Link("Update available — v\(update.version)", destination: update.url)
                            .foregroundStyle(Theme.accent)
                    } else if checkedOnce && !checking {
                        Label("Up to date", systemImage: "checkmark.circle")
                            .foregroundStyle(Theme.ok).font(.callout)
                    }
                    Spacer()
                    Button(checking ? "Checking…" : "Check for Updates") {
                        checking = true
                        Task { @MainActor in
                            await model.checkForUpdatesNow()
                            checking = false
                            checkedOnce = true
                        }
                    }
                    .disabled(checking)
                }
                Text("Checks the public GitHub releases page — one anonymous request, nothing about you is sent.")
                    .font(.caption2).foregroundStyle(.secondary)
                #endif
            }
            Section("Privacy") {
                Label("Local logs (Source B): UsageMeter reads only token counts, model names, and timestamps — never message content.",
                      systemImage: "lock.shield")
                    .font(.caption)
                #if !APPSTORE
                Label("Account (Source A): UsageMeter reads only your usage percentages and reset times from claude.ai — never conversation content. Only your login session is stored locally, and Log out wipes it.",
                      systemImage: "lock.shield")
                    .font(.caption)
                #endif
                Text("Everything stays on this Mac.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section {
                Text("UsageMeter is an independent tool, not affiliated with, endorsed by, or sponsored by Anthropic. Claude and Claude Code are trademarks of Anthropic PBC.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}
