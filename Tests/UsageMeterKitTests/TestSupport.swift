import Foundation
@testable import UsageMeterKit

enum Fixture {
    static func url(_ name: String, _ ext: String) -> URL {
        guard let url = Bundle.module.url(forResource: name, withExtension: ext, subdirectory: "Fixtures") else {
            fatalError("Missing fixture \(name).\(ext)")
        }
        return url
    }

    static func data(_ name: String, _ ext: String) -> Data {
        (try? Data(contentsOf: url(name, ext))) ?? Data()
    }
}

enum TestTime {
    static func date(_ string: String) -> Date {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = iso.date(from: string) { return d }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: string) ?? Date(timeIntervalSince1970: 0)
    }
}

func utcCalendar() -> Calendar {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "UTC") ?? .gmt
    return c
}

func makeRecord(
    id: String,
    model: String = "claude-opus-4-8",
    at iso: String,
    project: String = "proj",
    input: Int = 0,
    cacheCreation: Int = 0,
    cacheRead: Int = 0,
    output: Int = 0
) -> UsageRecord {
    UsageRecord(
        id: id,
        model: model,
        timestamp: TestTime.date(iso),
        usage: TokenUsage(inputTokens: input, cacheCreationTokens: cacheCreation,
                          cacheReadTokens: cacheRead, outputTokens: output),
        projectID: project
    )
}
