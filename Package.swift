// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "SessionHawk",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .library(
            name: "SessionHawkCore",
            targets: ["SessionHawkCore"]
        ),
        .executable(
            name: "SessionHawkHooks",
            targets: ["SessionHawkHooks"]
        ),
        .executable(
            name: "SessionHawkSetup",
            targets: ["SessionHawkSetup"]
        ),
        .executable(
            name: "SessionHawkApp",
            targets: ["SessionHawkApp"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/gonzalezreal/swift-markdown-ui", from: "2.4.1"),
    ],
    targets: [
        .target(
            name: "SessionHawkCore"
        ),
        .executableTarget(
            name: "SessionHawkHooks",
            dependencies: ["SessionHawkCore"]
        ),
        .executableTarget(
            name: "SessionHawkSetup",
            dependencies: ["SessionHawkCore"]
        ),
        .executableTarget(
            name: "SessionHawkApp",
            dependencies: [
                "SessionHawkCore",
                .product(name: "MarkdownUI", package: "swift-markdown-ui"),
            ],
            resources: [
                .process("Resources"),
            ]
        ),
        .testTarget(
            name: "SessionHawkCoreTests",
            dependencies: ["SessionHawkCore"]
        ),
        .testTarget(
            name: "SessionHawkAppTests",
            dependencies: ["SessionHawkApp", "SessionHawkCore"]
        ),
    ]
)
