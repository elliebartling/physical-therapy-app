// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "PTAppCore",
    platforms: [.iOS(.v26)],
    products: [
        .library(name: "DataKit", targets: ["DataKit"]),
        .library(name: "ParsingKit", targets: ["ParsingKit"]),
        .library(name: "SessionKit", targets: ["SessionKit"]),
        .library(name: "HistoryKit", targets: ["HistoryKit"]),
        .library(name: "UI", targets: ["UI"]),
    ],
    targets: [
        .target(name: "DataKit"),
        .target(name: "ParsingKit", dependencies: ["DataKit"]),
        .target(
            name: "SessionKit",
            dependencies: ["DataKit"],
            resources: [.process("Resources")]
        ),
        .target(name: "HistoryKit", dependencies: ["DataKit"]),
        .target(name: "UI", dependencies: ["DataKit", "ParsingKit", "SessionKit", "HistoryKit"]),
        .testTarget(name: "DataKitTests", dependencies: ["DataKit"]),
        .testTarget(name: "ParsingKitTests", dependencies: ["ParsingKit"], resources: [.process("Fixtures")]),
        .testTarget(name: "SessionKitTests", dependencies: ["SessionKit"]),
        .testTarget(name: "HistoryKitTests", dependencies: ["HistoryKit"]),
        .testTarget(name: "UITests", dependencies: ["UI"]),
    ]
)
