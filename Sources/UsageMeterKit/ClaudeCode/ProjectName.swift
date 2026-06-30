import Foundation

/// Best-effort, privacy-safe project display name derived purely from the folder
/// slug (we never read `cwd` or any message content).
///
/// Claude Code encodes the project path as a slug with `/` replaced by `-` and a
/// leading `-` (e.g. `-Users-me-Projects-usage-meter`). Recovering the original
/// path is inherently lossy when directory names contain hyphens, so we show the
/// trailing components as a readable label and keep the full slug available.
public enum ProjectName {
    public static func display(forSlug slug: String) -> String {
        let trimmed = slug.drop(while: { $0 == "-" })
        guard !trimmed.isEmpty else { return slug }
        let components = trimmed.split(separator: "-", omittingEmptySubsequences: true)
        guard !components.isEmpty else { return String(trimmed) }
        // Show the last up-to-two components (covers common `parent-child` and
        // single hyphenated names like `usage-meter`).
        let tail = components.suffix(2).joined(separator: "-")
        return tail.isEmpty ? String(trimmed) : tail
    }
}
