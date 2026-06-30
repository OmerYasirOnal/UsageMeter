import Testing
import Foundation
@testable import UsageMeterKit

@Suite struct PricingTests {
    @Test func loadsBundledRates() {
        let pricing = Pricing.loadBundled()
        #expect(pricing.rate(for: .opus) != nil)
        #expect(pricing.rate(for: .sonnet) != nil)
        // Unknown is never priced.
        #expect(pricing.rate(for: .unknown) == nil)
    }

    @Test func decodesRatesFromJSON() {
        let json = #"{"rates":{"opus":{"input":11.0,"output":22.0},"sonnet":{"input":1.0,"output":2.0}}}"#
        let pricing = Pricing.load(from: Data(json.utf8))
        #expect(pricing.rate(for: .opus) == ModelRate(input: 11.0, output: 22.0))
        #expect(pricing.rate(for: .sonnet) == ModelRate(input: 1.0, output: 2.0))
    }

    @Test func fallsBackToDefaultsOnGarbage() {
        let pricing = Pricing.load(from: Data("nope".utf8))
        #expect(pricing == Pricing.defaults)
    }

    @Test func ignoresUnknownKeysAndEmptyFallsBack() {
        let json = #"{"rates":{"banana":{"input":1.0,"output":2.0}}}"#
        let pricing = Pricing.load(from: Data(json.utf8))
        // No recognized families → defaults.
        #expect(pricing == Pricing.defaults)
    }

    // [29] Partial override is NOT merged with defaults (documents current behavior).
    @Test func partialOverrideDoesNotMergeDefaults() {
        let json = #"{"rates":{"opus":{"input":9.0,"output":9.0}}}"#
        let pricing = Pricing.load(from: Data(json.utf8))
        #expect(pricing.rate(for: .opus) == ModelRate(input: 9.0, output: 9.0))
        #expect(pricing.rate(for: .sonnet) == nil) // not merged from defaults
    }

    // [29] Family keys are matched case-insensitively.
    @Test func uppercaseFamilyKeyIsAccepted() {
        let json = #"{"rates":{"OPUS":{"input":1.0,"output":2.0}}}"#
        let pricing = Pricing.load(from: Data(json.utf8))
        #expect(pricing.rate(for: .opus) == ModelRate(input: 1.0, output: 2.0))
    }
}

@Suite struct UsageStoreTests {
    let fm = FileManager.default

    func makeStore() -> (UsageStore, URL) {
        let dir = fm.temporaryDirectory.appendingPathComponent("um-store-\(UUID().uuidString)", isDirectory: true)
        return (UsageStore(directory: dir), dir)
    }

    @Test func roundTripsCache() {
        let (store, dir) = makeStore()
        defer { try? fm.removeItem(at: dir) }

        let record = makeRecord(id: "r1", at: "2026-06-30T10:00:00.000Z", output: 42)
        var cache = CacheData()
        cache.files["/tmp/a.jsonl"] = CachedFile(
            stamp: FileStamp(modifiedAt: TestTime.date("2026-06-30T10:00:00.000Z"), size: 10),
            projectID: "proj",
            records: [record]
        )
        cache.lastUpdated = TestTime.date("2026-06-30T12:00:00.000Z")

        #expect(store.save(cache))
        let loaded = store.load()
        #expect(loaded.files.count == 1)
        #expect(loaded.files["/tmp/a.jsonl"]?.projectID == "proj")
        #expect(loaded.allRecords.first?.id == "r1")
        #expect(loaded.lastUpdated == cache.lastUpdated)
    }

    @Test func missingFileLoadsEmpty() {
        let (store, dir) = makeStore()
        defer { try? fm.removeItem(at: dir) }
        #expect(store.load() == CacheData.empty)
    }

    @Test func clearRemovesCache() {
        let (store, dir) = makeStore()
        defer { try? fm.removeItem(at: dir) }
        store.save(CacheData(lastUpdated: TestTime.date("2026-06-30T12:00:00.000Z")))
        store.clear()
        #expect(store.load() == CacheData.empty)
    }

    @Test func versionMismatchLoadsEmpty() throws {
        let (store, dir) = makeStore()
        defer { try? fm.removeItem(at: dir) }
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let bogus = #"{"version":999,"files":{}}"#
        try Data(bogus.utf8).write(to: store.fileURL)
        #expect(store.load() == CacheData.empty)
    }

    // [30] Corrupt-but-present cache loads empty rather than crashing.
    @Test func corruptDataLoadsEmpty() throws {
        let (store, dir) = makeStore()
        defer { try? fm.removeItem(at: dir) }
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data("{ this is not valid json".utf8).write(to: store.fileURL)
        #expect(store.load() == CacheData.empty)
    }
}

// [30] Status persistence lives in its own store now (sources decoupled in storage).
@Suite struct StatusStoreTests {
    let fm = FileManager.default

    func makeStore() -> (StatusStore, URL) {
        let dir = fm.temporaryDirectory.appendingPathComponent("um-status-\(UUID().uuidString)", isDirectory: true)
        return (StatusStore(directory: dir), dir)
    }

    @Test func roundTripsStatusWithIncidentsAndFetchedAt() {
        let (store, dir) = makeStore()
        defer { try? fm.removeItem(at: dir) }
        let status = ServiceStatus(
            indicator: .minor,
            description: "Degraded",
            incidents: [IncidentSummary(id: "i1", name: "Blip", status: "investigating",
                                        impact: "minor", shortlink: "https://x")],
            scheduledMaintenances: [],
            fetchedAt: TestTime.date("2026-06-30T12:00:00.000Z")
        )
        #expect(store.save(status))
        let loaded = store.load()
        #expect(loaded == status)
        #expect(loaded?.incidents.first?.shortlink == "https://x")
        #expect(loaded?.fetchedAt == status.fetchedAt)
    }

    @Test func missingFileLoadsNil() {
        let (store, dir) = makeStore()
        defer { try? fm.removeItem(at: dir) }
        #expect(store.load() == nil)
    }

    @Test func clearRemovesStatus() {
        let (store, dir) = makeStore()
        defer { try? fm.removeItem(at: dir) }
        store.save(ServiceStatus(indicator: .none, description: "ok"))
        store.clear()
        #expect(store.load() == nil)
    }
}

@Suite struct ProjectNameTests {
    @Test func showsTrailingComponents() {
        #expect(ProjectName.display(forSlug: "-Users-me-Projects-usage-meter") == "usage-meter")
        #expect(ProjectName.display(forSlug: "-tmp") == "tmp")
    }

    @Test func handlesEmptyAndDashOnly() {
        #expect(ProjectName.display(forSlug: "") == "")
        #expect(ProjectName.display(forSlug: "---") == "---")
    }
}
