import Testing
import Foundation
@testable import UsageMeterKit

@Suite struct StatusDecodingTests {
    @Test func decodesOperationalSummary() throws {
        let status = try StatusDecoder.decodeSummary(Fixture.data("status_operational", "json"))
        #expect(status.indicator == .none)
        #expect(status.indicator.isOperational)
        #expect(status.description == "All Systems Operational")
        #expect(status.incidents.isEmpty)
        #expect(status.hasActiveIssues == false)
    }

    @Test func decodesDegradedSummaryWithIncidents() throws {
        let status = try StatusDecoder.decodeSummary(Fixture.data("status_degraded", "json"))
        #expect(status.indicator == .major)
        #expect(status.description == "Partial Outage")
        #expect(status.incidents.count == 1)
        #expect(status.incidents.first?.name == "Elevated error rates on the API")
        #expect(status.incidents.first?.impact == "major")
        #expect(status.incidents.first?.shortlink == "https://stspg.io/abc123")
        #expect(status.scheduledMaintenances.count == 1)
        #expect(status.hasActiveIssues)
    }

    @Test func unknownIndicatorFallsBackGracefully() {
        let json = #"{"status":{"indicator":"weird","description":"?"}}"#
        let status = try? StatusDecoder.decodeSummary(Data(json.utf8))
        #expect(status?.indicator == .unknown)
    }

    @Test func missingStatusObjectStillDecodes() {
        let json = #"{"incidents":[]}"#
        let status = try? StatusDecoder.decodeSummary(Data(json.utf8))
        #expect(status?.indicator == .unknown)
        #expect(status?.description == "Status unknown")
    }

    @Test func garbageThrows() {
        #expect(throws: (any Error).self) {
            _ = try StatusDecoder.decodeSummary(Data("not json".utf8))
        }
    }

    @Test func stubClientReturnsConfiguredValue() async throws {
        let expected = ServiceStatus(indicator: .minor, description: "Test")
        let client = StubStatusClient(expected)
        let result = try await client.fetch()
        #expect(result == expected)
    }
}
