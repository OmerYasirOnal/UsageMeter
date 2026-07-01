import Testing
import Foundation
@testable import UsageMeterKit

@Suite struct CostCalculatorTests {
    let calc = CostCalculator(pricing: .defaults)

    @Test func appliesFullCostModel() {
        // opus = input 5 / output 25 per 1M.
        let usage = TokenUsage(inputTokens: 100, cacheCreationTokens: 200,
                               cacheReadTokens: 1000, outputTokens: 50)
        // 100*5 + 200*5*1.25 + 1000*5*0.10 + 50*25 = 500 + 1250 + 500 + 1250 = 3500
        let expected = 3500.0 / 1_000_000.0
        let cost = calc.cost(usage: usage, family: .opus)
        #expect(cost != nil)
        #expect(abs((cost ?? 0) - expected) < 1e-12)
    }

    @Test func cacheReadIsTenPercentOfInputRate() {
        let usage = TokenUsage(cacheReadTokens: 1_000_000)
        // 1,000,000 * 5 * 0.10 / 1,000,000 = 0.5
        #expect(abs((calc.cost(usage: usage, family: .opus) ?? 0) - 0.5) < 1e-9)
    }

    @Test func cacheWriteIs125PercentOfInputRate() {
        let usage = TokenUsage(cacheCreationTokens: 1_000_000)
        // 1,000,000 * 5 * 1.25 / 1,000,000 = 6.25
        #expect(abs((calc.cost(usage: usage, family: .opus) ?? 0) - 6.25) < 1e-9)
    }

    @Test func oneHourCacheWritesBillAtDoubleInputRate() {
        let usage = TokenUsage(cacheCreationTokens: 1_000_000, cacheCreation1hTokens: 1_000_000)
        // 1,000,000 * 5 * 2.0 / 1,000,000 = 10.0
        #expect(abs((calc.cost(usage: usage, family: .opus) ?? 0) - 10.0) < 1e-9)
    }

    @Test func mixedTTLCacheWritesSplitTheMultipliers() {
        let usage = TokenUsage(cacheCreationTokens: 1_000_000, cacheCreation1hTokens: 400_000)
        // 600,000*5*1.25 + 400,000*5*2.0 = 3,750,000 + 4,000,000 = 7,750,000 → 7.75
        #expect(abs((calc.cost(usage: usage, family: .opus) ?? 0) - 7.75) < 1e-9)
    }

    @Test func oneHourPortionIsClampedToTheTotal() {
        // Defensive: malformed input where 1h > total must not go negative.
        let usage = TokenUsage(cacheCreationTokens: 100, cacheCreation1hTokens: 200)
        // Clamped to all-1h: 100 * 5 * 2.0 / 1,000,000
        #expect(abs((calc.cost(usage: usage, family: .opus) ?? 0) - (1000.0 / 1_000_000.0)) < 1e-12)
    }

    @Test func unknownFamilyIsNotApplicable() {
        let usage = TokenUsage(inputTokens: 1000, outputTokens: 1000)
        #expect(calc.cost(usage: usage, family: .unknown) == nil)
        #expect(calc.cost(usage: usage, model: "<synthetic>") == nil)
    }

    @Test func totalCostSumsPricedAndIgnoresUnpriced() {
        let mixed: [ModelFamily: TokenUsage] = [
            .opus: TokenUsage(outputTokens: 1_000_000),     // 25
            .unknown: TokenUsage(outputTokens: 1_000_000)   // n/a, ignored
        ]
        let total = calc.totalCost(mixed)
        #expect(total != nil)
        #expect(abs((total ?? 0) - 25.0) < 1e-9)
    }

    @Test func totalCostIsNilWhenEverythingUnpriced() {
        let onlyUnknown: [ModelFamily: TokenUsage] = [.unknown: TokenUsage(outputTokens: 999)]
        #expect(calc.totalCost(onlyUnknown) == nil)
    }

    @Test func resolvesFamilyFromModelString() {
        let usage = TokenUsage(outputTokens: 1_000_000) // 1M output
        #expect(abs((calc.cost(usage: usage, model: "claude-sonnet-4-6") ?? 0) - 15.0) < 1e-9)
        #expect(abs((calc.cost(usage: usage, model: "claude-haiku-4-5-20251001") ?? 0) - 5.0) < 1e-9)
    }
}
