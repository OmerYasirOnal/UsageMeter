import Foundation
import Testing
@testable import UsageMeterKit

@Suite("UpdateChecker")
struct UpdateCheckerTests {
    @Test func parsesLatestReleaseTag() throws {
        let json = #"{"tag_name":"v0.3.0","html_url":"https://github.com/OmerYasirOnal/UsageMeter/releases/tag/v0.3.0","draft":false,"prerelease":false}"#
        let release = try #require(UpdateChecker.decodeLatest(Data(json.utf8)))
        #expect(release.version == "0.3.0")
        #expect(release.url.absoluteString.contains("/releases/tag/v0.3.0"))
    }

    @Test func ignoresDraftsAndPrereleases() {
        let draft = #"{"tag_name":"v9.9.9","html_url":"https://example.com","draft":true,"prerelease":false}"#
        #expect(UpdateChecker.decodeLatest(Data(draft.utf8)) == nil)
        let pre = #"{"tag_name":"v9.9.9","html_url":"https://example.com","draft":false,"prerelease":true}"#
        #expect(UpdateChecker.decodeLatest(Data(pre.utf8)) == nil)
    }

    @Test func semverComparison() {
        #expect(UpdateChecker.isNewer("0.3.0", than: "0.2.1"))
        #expect(UpdateChecker.isNewer("0.2.10", than: "0.2.9"))
        #expect(UpdateChecker.isNewer("1.0", than: "0.9.9"))
        #expect(!UpdateChecker.isNewer("0.2.1", than: "0.2.1"))
        #expect(!UpdateChecker.isNewer("0.2.0", than: "0.2.1"))
        // Longer version with trailing zeros is not newer.
        #expect(!UpdateChecker.isNewer("0.2.1.0", than: "0.2.1"))
        // Garbage never reports newer (fail safe: no false update prompts).
        #expect(!UpdateChecker.isNewer("abc", than: "0.2.1"))
    }

    @Test func stripsLeadingV() {
        #expect(UpdateChecker.normalize("v0.3.0") == "0.3.0")
        #expect(UpdateChecker.normalize("0.3.0") == "0.3.0")
    }
}
