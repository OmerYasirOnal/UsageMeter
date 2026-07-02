import SwiftUI
import AppKit
import Charts
import UniformTypeIdentifiers
import UsageMeterKit

/// Stage-0 team view: the admin imports members' `.umteam` files (exported from
/// their own UsageMeters) and sees the team at a glance. Serverless — files
/// arrive by whatever channel the team already uses.
struct TeamCard: View {
    @StateObject private var store = TeamFileStore()
    @State private var dropTargeted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Team").font(.title3.bold())
                    Text("Import your team's .umteam summaries — stats only, nothing else travels.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Add Files…") { store.addViaPanel() }
            }

            if store.entries.isEmpty {
                emptyState
            } else {
                table
                if store.entries.count > 1 { chart }
            }
        }
        .card()
        .onDrop(of: [.fileURL], isTargeted: $dropTargeted) { providers in
            store.addDropped(providers)
        }
        .overlay {
            if dropTargeted {
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(Theme.accent, style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
            }
        }
        .task { store.load() }
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: "person.2").font(.title2).foregroundStyle(.secondary)
            Text("No team files yet").font(.callout.weight(.medium))
            Text("Each member exports Export ▸ Team summary from their UsageMeter and sends you the file. Drop the files here.")
                .font(.caption).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 90)
    }

    private var table: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Member").frame(maxWidth: .infinity, alignment: .leading)
                Text("Tokens · 90d").frame(width: 110, alignment: .trailing)
                Text("API value").frame(width: 90, alignment: .trailing)
                Text("7-day Δ").frame(width: 70, alignment: .trailing)
                Text("Last active").frame(width: 90, alignment: .trailing)
                Color.clear.frame(width: 24)
            }
            .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            .padding(.vertical, 6)
            Divider()
            ForEach(store.entries) { entry in
                let row = entry.row
                HStack {
                    Text(row.member).frame(maxWidth: .infinity, alignment: .leading)
                        .help("Summary generated \(row.generatedAt.formatted(date: .abbreviated, time: .shortened))")
                    Text(Formatting.tokens(row.windowTokens))
                        .monospacedDigit().frame(width: 110, alignment: .trailing)
                    Text(row.windowCost.map { Formatting.cost($0) } ?? "—")
                        .monospacedDigit().frame(width: 90, alignment: .trailing)
                    Text(row.weekOverWeek.map { String(format: "%+.0f%%", $0 * 100) } ?? "—")
                        .monospacedDigit().frame(width: 70, alignment: .trailing)
                        .foregroundStyle(.secondary)
                    Text(row.lastActiveDay ?? "—")
                        .frame(width: 90, alignment: .trailing).foregroundStyle(.secondary)
                    Button {
                        store.remove(entry)
                    } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                    .help("Remove \(row.member)")
                    .frame(width: 24)
                }
                .font(.callout)
                .padding(.vertical, 6)
                Divider()
            }
        }
    }

    /// Per-member 90-day tokens — one hue, magnitude only.
    private var chart: some View {
        Chart(store.entries) { entry in
            BarMark(
                x: .value("Tokens", entry.row.windowTokens),
                y: .value("Member", entry.row.member)
            )
            .foregroundStyle(Theme.data)
            .cornerRadius(3)
        }
        .chartXAxis {
            AxisMarks { value in
                AxisGridLine()
                AxisValueLabel {
                    if let i = value.as(Int.self) { Text(Formatting.axisTokens(i)).font(.caption2) }
                }
            }
        }
        .frame(height: CGFloat(max(60, store.entries.count * 26)))
    }
}

/// Owns the imported `.umteam` files: copies live in Application
/// Support/UsageMeter/team/ so the team view survives relaunches.
@MainActor
final class TeamFileStore: ObservableObject {
    struct Entry: Identifiable {
        let url: URL
        let summary: TeamSummary
        let row: TeamMemberRow
        var id: String { url.path }
    }

    @Published private(set) var entries: [Entry] = []

    private var directory: URL {
        UsageStore.defaultDirectory().appendingPathComponent("team", isDirectory: true)
    }

    func load() {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil)) ?? []
        entries = files
            .filter { $0.pathExtension == TeamSummary.fileExtension }
            .compactMap { url in
                guard let data = try? Data(contentsOf: url),
                      let summary = TeamSummary.decode(data) else { return nil }
                return Entry(url: url, summary: summary,
                             row: TeamMemberRow.make(from: summary, now: Date()))
            }
            .sorted { $0.row.windowTokens > $1.row.windowTokens }
    }

    func addViaPanel() {
        NSApp.activate(ignoringOtherApps: true)
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [UTType(filenameExtension: TeamSummary.fileExtension) ?? .json]
        if panel.runModal() == .OK { add(urls: panel.urls) }
    }

    func addDropped(_ providers: [NSItemProvider]) -> Bool {
        var accepted = false
        for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            accepted = true
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url else { return }
                Task { @MainActor in self.add(urls: [url]) }
            }
        }
        return accepted
    }

    /// Validate + copy into the store directory (newer file for the same member
    /// replaces the older copy), then reload.
    func add(urls: [URL]) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for url in urls {
            guard url.pathExtension == TeamSummary.fileExtension,
                  let data = try? Data(contentsOf: url),
                  let summary = TeamSummary.decode(data) else { continue }
            // One file per member: stable name keyed by the member string.
            let safe = summary.member.replacingOccurrences(of: "/", with: "-")
            let target = directory.appendingPathComponent("\(safe).\(TeamSummary.fileExtension)")
            if let existing = try? Data(contentsOf: target),
               let current = TeamSummary.decode(existing),
               current.generatedAt > summary.generatedAt {
                continue // keep the newer copy we already have
            }
            try? data.write(to: target, options: [.atomic])
        }
        load()
    }

    func remove(_ entry: Entry) {
        try? FileManager.default.removeItem(at: entry.url)
        load()
    }
}
