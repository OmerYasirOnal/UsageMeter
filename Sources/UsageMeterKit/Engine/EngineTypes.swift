import Foundation

/// Runtime configuration for the data engine.
public struct EngineConfiguration: Sendable, Equatable {
    /// Directories to scan for Claude Code logs (Source B).
    public var projectRoots: [URL]
    /// How often the app refreshes (seconds). Source A/C clients are polite on top
    /// of this; the UI also refreshes on demand when the popover opens.
    public var refreshInterval: TimeInterval

    public init(
        projectRoots: [URL] = ProjectScanner.defaultRoots(),
        refreshInterval: TimeInterval = 180
    ) {
        self.projectRoots = projectRoots
        self.refreshInterval = refreshInterval
    }
}

/// An immutable, Sendable snapshot of everything the UI renders.
public struct EngineSnapshot: Sendable, Equatable {
    public var claudeCode: ClaudeCodeStats
    public var status: ServiceStatus?
    public var account: AccountUsage?
    public var lastUpdated: Date?

    public init(
        claudeCode: ClaudeCodeStats = .empty,
        status: ServiceStatus? = nil,
        account: AccountUsage? = nil,
        lastUpdated: Date? = nil
    ) {
        self.claudeCode = claudeCode
        self.status = status
        self.account = account
        self.lastUpdated = lastUpdated
    }

    public static let empty = EngineSnapshot()
}
