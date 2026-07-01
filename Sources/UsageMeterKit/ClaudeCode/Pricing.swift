import Foundation

/// USD rate (per 1,000,000 tokens) for a model family.
public struct ModelRate: Codable, Sendable, Equatable {
    /// Applies to fresh input. Cache-write and cache-read are derived from this
    /// in `CostCalculator` via fixed multipliers.
    public let input: Double
    public let output: Double

    public init(input: Double, output: Double) {
        self.input = input
        self.output = output
    }
}

/// The pricing table, loaded from `pricing.json` (editable resource) with a
/// hard-coded fallback so the app never depends on the file being present.
public struct Pricing: Sendable, Equatable {
    public let rates: [ModelFamily: ModelRate]

    public init(rates: [ModelFamily: ModelRate]) {
        self.rates = rates
    }

    public func rate(for family: ModelFamily) -> ModelRate? {
        rates[family]
    }

    /// Built-in defaults — kept in sync with `Resources/pricing.json`. These are
    /// ESTIMATES (verified 2026-07-02); confirm on Anthropic's official pricing page.
    public static let defaults = Pricing(rates: [
        .opus:   ModelRate(input: 5.0,  output: 25.0),
        .sonnet: ModelRate(input: 3.0,  output: 15.0),
        .haiku:  ModelRate(input: 1.0,  output: 5.0),
        .fable:  ModelRate(input: 10.0, output: 50.0),
        .mythos: ModelRate(input: 10.0, output: 50.0)
    ])

    /// On-disk shape of `pricing.json`.
    private struct File: Decodable {
        let rates: [String: ModelRate]
    }

    /// Load from explicit data; falls back to `defaults` on any decoding error.
    public static func load(from data: Data) -> Pricing {
        guard let file = try? JSONDecoder().decode(File.self, from: data) else {
            return .defaults
        }
        var mapped: [ModelFamily: ModelRate] = [:]
        for (key, rate) in file.rates {
            // Accept exact family keys ("opus", "sonnet", ...). Unknown keys ignored.
            if let family = ModelFamily(rawValue: key.lowercased()), family != .unknown {
                mapped[family] = rate
            }
        }
        return mapped.isEmpty ? .defaults : Pricing(rates: mapped)
    }

    /// Load the bundled `pricing.json`, falling back to `defaults`.
    /// - Parameter bundle: pass `nil` (default) to use the package resource bundle.
    ///
    /// Note: this touches `Bundle.module`, whose SwiftPM accessor `fatalError`s if
    /// its resource bundle is missing. Safe under `swift test`/`swift run`; for the
    /// shipped `.app` use `loadFromMainBundle()` instead.
    public static func loadBundled(bundle: Bundle? = nil) -> Pricing {
        let resolved = bundle ?? .module
        guard let url = resolved.url(forResource: "pricing", withExtension: "json"),
              let data = try? Data(contentsOf: url) else {
            return .defaults
        }
        return load(from: data)
    }

    /// Load `pricing.json` from the host app's main bundle (the assembled `.app`'s
    /// `Contents/Resources`). Never touches `Bundle.module`, so it cannot crash an
    /// unbundled `swift run`; falls back to `defaults` when the file is absent.
    public static func loadFromMainBundle() -> Pricing {
        guard let url = Bundle.main.url(forResource: "pricing", withExtension: "json"),
              let data = try? Data(contentsOf: url) else {
            return .defaults
        }
        return load(from: data)
    }
}
