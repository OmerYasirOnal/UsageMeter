import Foundation

/// The token counts we care about from a Claude Code `message.usage` block.
///
/// Privacy note: these are the *only* numeric fields we ever read from a log line.
/// We never read or store message content. See `JSONLParser`.
public struct TokenUsage: Codable, Sendable, Equatable, Hashable {
    /// Fresh input tokens (not served from / written to cache).
    public var inputTokens: Int
    /// Context written to the prompt cache — ALL TTLs
    /// (`cache_creation_input_tokens`, or the sum of the `cache_creation` split).
    public var cacheCreationTokens: Int
    /// The 1-hour-TTL portion of `cacheCreationTokens`
    /// (`cache_creation.ephemeral_1h_input_tokens`). Billed at 2x the input rate
    /// vs 1.25x for the 5-minute tier — see `CostCalculator`. Always
    /// <= `cacheCreationTokens`; NOT counted again in `totalTokens`.
    public var cacheCreation1hTokens: Int
    /// Context served from the prompt cache (`cache_read_input_tokens`).
    public var cacheReadTokens: Int
    /// Response tokens.
    public var outputTokens: Int

    public init(
        inputTokens: Int = 0,
        cacheCreationTokens: Int = 0,
        cacheCreation1hTokens: Int = 0,
        cacheReadTokens: Int = 0,
        outputTokens: Int = 0
    ) {
        self.inputTokens = inputTokens
        self.cacheCreationTokens = cacheCreationTokens
        self.cacheCreation1hTokens = cacheCreation1hTokens
        self.cacheReadTokens = cacheReadTokens
        self.outputTokens = outputTokens
    }

    public static let zero = TokenUsage()

    /// Every token counted in this record, regardless of bucket.
    /// (`cacheCreation1hTokens` is a sub-bucket of `cacheCreationTokens`,
    /// so it is deliberately not added here.)
    public var totalTokens: Int {
        inputTokens + cacheCreationTokens + cacheReadTokens + outputTokens
    }

    public static func + (lhs: TokenUsage, rhs: TokenUsage) -> TokenUsage {
        TokenUsage(
            inputTokens: lhs.inputTokens + rhs.inputTokens,
            cacheCreationTokens: lhs.cacheCreationTokens + rhs.cacheCreationTokens,
            cacheCreation1hTokens: lhs.cacheCreation1hTokens + rhs.cacheCreation1hTokens,
            cacheReadTokens: lhs.cacheReadTokens + rhs.cacheReadTokens,
            outputTokens: lhs.outputTokens + rhs.outputTokens
        )
    }

    public static func += (lhs: inout TokenUsage, rhs: TokenUsage) {
        lhs = lhs + rhs
    }
}
