// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "UsageMeter",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        // The engine: 100% headless-testable. Sources B (Claude Code logs) and
        // C (status page) live here, plus the Source A protocol + local-only fallback.
        .library(name: "UsageMeterKit", targets: ["UsageMeterKit"]),
        // The menu-bar app: a thin SwiftUI shell over UsageMeterKit.
        .executable(name: "UsageMeter", targets: ["UsageMeter"])
    ],
    targets: [
        .target(
            name: "UsageMeterKit",
            resources: [
                .copy("Resources/pricing.json")
            ],
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
        .executableTarget(
            name: "UsageMeter",
            dependencies: ["UsageMeterKit"],
            swiftSettings: [
                // SwiftUI + strict concurrency is fine here; everything UI-facing is
                // @MainActor and the engine is an actor. Keep v6 for consistency.
                .swiftLanguageMode(.v6)
            ]
        ),
        .testTarget(
            name: "UsageMeterKitTests",
            dependencies: ["UsageMeterKit"],
            resources: [
                .copy("Fixtures")
            ],
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        )
    ]
)
