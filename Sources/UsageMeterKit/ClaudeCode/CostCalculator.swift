import Foundation

/// Turns token counts into estimated USD cost using the Section 4.4 model:
///   fresh input → input_tokens × input_rate
///   cache write → cache_creation_input_tokens × input_rate × 1.25
///   cache read  → cache_read_input_tokens × input_rate × 0.10
///   output      → output_tokens × output_rate
/// Rates are per 1,000,000 tokens. Unknown/unpriced families return `nil` (n/a).
public struct CostCalculator: Sendable {
    public static let cacheWriteMultiplier = 1.25
    public static let cacheReadMultiplier = 0.10
    private static let perTokenDivisor = 1_000_000.0

    public let pricing: Pricing

    public init(pricing: Pricing) {
        self.pricing = pricing
    }

    /// Estimated cost for a usage bucket attributed to a model family.
    /// Returns `nil` when the family is `.unknown` or has no rate entry.
    public func cost(usage: TokenUsage, family: ModelFamily) -> Double? {
        guard family.isPriced, let rate = pricing.rate(for: family) else { return nil }
        let inputCost = Double(usage.inputTokens) * rate.input
        let cacheWriteCost = Double(usage.cacheCreationTokens) * rate.input * Self.cacheWriteMultiplier
        let cacheReadCost = Double(usage.cacheReadTokens) * rate.input * Self.cacheReadMultiplier
        let outputCost = Double(usage.outputTokens) * rate.output
        return (inputCost + cacheWriteCost + cacheReadCost + outputCost) / Self.perTokenDivisor
    }

    public func cost(usage: TokenUsage, model: String) -> Double? {
        cost(usage: usage, family: ModelFamily(modelIdentifier: model))
    }

    /// Sum costs over a set of per-family buckets. Returns `nil` only when *every*
    /// contributing family is unpriced; otherwise sums the priced portion and
    /// ignores the n/a portion (so a mixed total is still informative).
    public func totalCost(_ byFamily: [ModelFamily: TokenUsage]) -> Double? {
        var total = 0.0
        var anyPriced = false
        for (family, usage) in byFamily {
            if let c = cost(usage: usage, family: family) {
                total += c
                anyPriced = true
            }
        }
        return anyPriced ? total : nil
    }
}
