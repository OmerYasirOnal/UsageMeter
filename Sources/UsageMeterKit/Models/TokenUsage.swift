import Foundation

/// The four token counts we care about from a Claude Code `message.usage` block.
///
/// Privacy note: these are the *only* numeric fields we ever read from a log line.
/// We never read or store message content. See `JSONLParser`.
public struct TokenUsage: Codable, Sendable, Equatable, Hashable {
    /// Fresh input tokens (not served from / written to cache).
    public var inputTokens: Int
    /// Context written to the prompt cache (`cache_creation_input_tokens`).
    public var cacheCreationTokens: Int
    /// Context served from the prompt cache (`cache_read_input_tokens`).
    public var cacheReadTokens: Int
    /// Response tokens.
    public var outputTokens: Int

    public init(
        inputTokens: Int = 0,
        cacheCreationTokens: Int = 0,
        cacheReadTokens: Int = 0,
        outputTokens: Int = 0
    ) {
        self.inputTokens = inputTokens
        self.cacheCreationTokens = cacheCreationTokens
        self.cacheReadTokens = cacheReadTokens
        self.outputTokens = outputTokens
    }

    public static let zero = TokenUsage()

    /// Every token counted in this record, regardless of bucket.
    public var totalTokens: Int {
        inputTokens + cacheCreationTokens + cacheReadTokens + outputTokens
    }

    public static func + (lhs: TokenUsage, rhs: TokenUsage) -> TokenUsage {
        TokenUsage(
            inputTokens: lhs.inputTokens + rhs.inputTokens,
            cacheCreationTokens: lhs.cacheCreationTokens + rhs.cacheCreationTokens,
            cacheReadTokens: lhs.cacheReadTokens + rhs.cacheReadTokens,
            outputTokens: lhs.outputTokens + rhs.outputTokens
        )
    }

    public static func += (lhs: inout TokenUsage, rhs: TokenUsage) {
        lhs = lhs + rhs
    }
}
