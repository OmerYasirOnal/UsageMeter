import Foundation

/// Parses Claude Code session JSONL into privacy-safe `UsageRecord`s.
///
/// Implements the Section 4.3 rules:
///  1. Read line by line; tolerate malformed/partial lines (skip, never crash).
///  2. Only process `assistant` records that contain `message.usage`.
///  3. Skip sidechain/subagent records (`isSidechain == true`) to avoid double-counting.
///  4. Carry a dedup id (prefer `requestId`, fall back to `uuid`); global dedup
///     happens in `DailyAggregator` so it spans files correctly.
///
/// Privacy: the only fields ever read are `type`, `isSidechain`, `requestId`,
/// `uuid`, `timestamp`, `message.model`, and `message.usage.*` (numeric token
/// counts only, incl. the nested `usage.cache_creation` TTL split). Message
/// content (`message.content`) is never touched.
public struct JSONLParser: Sendable {
    public init() {}

    /// Parse a file on disk. Returns `[]` on read failure (never throws).
    public func parse(fileAt url: URL, projectID: String) -> [UsageRecord] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        return parse(data: data, projectID: projectID, source: url.lastPathComponent)
    }

    /// Parse raw JSONL bytes.
    /// - Parameter source: a short identifier (e.g. filename) used only to synthesize
    ///   a stable id for the rare record that has neither `requestId` nor `uuid`.
    public func parse(data: Data, projectID: String, source: String = "") -> [UsageRecord] {
        guard !data.isEmpty else { return [] }

        let isoWithFraction = ISO8601DateFormatter()
        isoWithFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let isoPlain = ISO8601DateFormatter()
        isoPlain.formatOptions = [.withInternetDateTime]

        // Lossy UTF-8 decode so a single bad byte doesn't drop the whole file.
        // A trailing partial line (active session) simply fails JSON parsing and
        // is skipped per-line below.
        let text = String(decoding: data, as: UTF8.self)
        return parse(text: text, projectID: projectID, source: source,
                     isoWithFraction: isoWithFraction, isoPlain: isoPlain)
    }

    private func parse(
        text: String,
        projectID: String,
        source: String,
        isoWithFraction: ISO8601DateFormatter,
        isoPlain: ISO8601DateFormatter
    ) -> [UsageRecord] {
        var records: [UsageRecord] = []
        var lineIndex = -1

        text.enumerateLines { line, _ in
            lineIndex += 1
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { return }
            guard let lineData = trimmed.data(using: .utf8) else { return }
            guard let object = try? JSONSerialization.jsonObject(with: lineData),
                  let dict = object as? [String: Any] else {
                return // malformed / partial line — skip
            }

            // Rule 2: only assistant records with message.usage. Require an
            // explicit `assistant` type — records missing the field (or of another
            // type) are skipped, matching "assistant records only".
            guard (dict["type"] as? String) == "assistant" else { return }
            guard let message = dict["message"] as? [String: Any],
                  let usageDict = message["usage"] as? [String: Any] else {
                return
            }

            // Rule 3: skip sidechain/subagent records.
            if let sidechain = dict["isSidechain"] as? Bool, sidechain {
                return
            }

            // Cache writes: prefer the legacy aggregate; the `cache_creation`
            // split object (ephemeral_5m/1h) is the forward-compatible source
            // and also tells us the 1h-TTL portion (billed 2x, not 1.25x).
            let legacyCacheWrite = Self.int(usageDict["cache_creation_input_tokens"])
            var oneHourCacheWrite = 0
            var splitTotal = 0
            if let split = usageDict["cache_creation"] as? [String: Any] {
                oneHourCacheWrite = Self.int(split["ephemeral_1h_input_tokens"])
                splitTotal = Self.int(split["ephemeral_5m_input_tokens"]) + oneHourCacheWrite
            }
            let cacheWriteTotal = legacyCacheWrite > 0 ? legacyCacheWrite : splitTotal

            let usage = TokenUsage(
                inputTokens: Self.int(usageDict["input_tokens"]),
                cacheCreationTokens: cacheWriteTotal,
                cacheCreation1hTokens: min(oneHourCacheWrite, cacheWriteTotal),
                cacheReadTokens: Self.int(usageDict["cache_read_input_tokens"]),
                outputTokens: Self.int(usageDict["output_tokens"])
            )

            let model = (message["model"] as? String) ?? "unknown"

            // Rule 4: dedup id (prefer requestId, then uuid). For the rare record
            // with neither, synthesize a per-(project, file, line) id so id-less
            // records can't collide across different inputs.
            let id: String
            if let requestID = dict["requestId"] as? String, !requestID.isEmpty {
                id = requestID
            } else if let uuid = dict["uuid"] as? String, !uuid.isEmpty {
                id = uuid
            } else {
                id = "\(projectID)/\(source)#\(lineIndex)"
            }

            // A record we cannot place in time is treated as malformed and skipped,
            // so day/block math never gets a spurious 1970 bucket.
            guard let tsString = dict["timestamp"] as? String,
                  let timestamp = isoWithFraction.date(from: tsString)
                    ?? isoPlain.date(from: tsString) else {
                return
            }

            records.append(
                UsageRecord(id: id, model: model, timestamp: timestamp, usage: usage, projectID: projectID)
            )
        }

        return records
    }

    /// Defensive int extraction: accepts Int, Double, or numeric NSNumber; else 0.
    private static func int(_ value: Any?) -> Int {
        if let n = value as? NSNumber { return n.intValue }
        if let i = value as? Int { return i }
        if let d = value as? Double { return Int(d) }
        return 0
    }
}
