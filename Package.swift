// swift-tools-version: 6.2
// Every target the waves need is declared here (spec W3). Feature branches never edit this file.
// macOS-only targets are declared inside `#if os(macOS)`, so Linux builds and tests only the portable core.
import PackageDescription

let swift6: [SwiftSetting] = [.swiftLanguageMode(.v6)]

/// The area cores. Each is empty until its wave and depends only on the shared contracts.
let areaCores = [
    "CaptureCore", "QuickAccessCore", "EditorCore", "RecordingCore", "MotionCore",
    "TextCore", "ProvenanceCore", "SearchCore", "CollectionsCore", "GuideCore", "AICore",
]

var products: [Product] = []
var targets: [Target] = [
    .target(name: "BugeyeCore", swiftSettings: swift6),
    .target(name: "BugeyeFeatures", dependencies: ["BugeyeCore"], swiftSettings: swift6),
    .target(name: "BugeyeTestSupport", dependencies: ["BugeyeCore"], swiftSettings: swift6),
    .testTarget(
        name: "BugeyeCoreTests", dependencies: ["BugeyeCore", "BugeyeTestSupport"], swiftSettings: swift6),
    .testTarget(
        name: "BugeyeFeaturesTests", dependencies: ["BugeyeFeatures", "BugeyeTestSupport"],
        swiftSettings: swift6),
    .testTarget(
        name: "BugeyeTestSupportTests", dependencies: ["BugeyeTestSupport"], swiftSettings: swift6),
]

for name in areaCores {
    targets.append(
        .target(
            name: name, dependencies: ["BugeyeCore", "BugeyeFeatures"], path: "Sources/Core/\(name)",
            swiftSettings: swift6))
    targets.append(
        .testTarget(
            name: "\(name)Tests", dependencies: [.target(name: name), "BugeyeTestSupport"],
            // Recorded fixtures and goldens; every area has the folder so no wave edits this file for it.
            resources: [.copy("Fixtures")],
            swiftSettings: swift6))
}

#if os(macOS)
    products.append(.executable(name: "BugeyeApp", targets: ["BugeyeApp"]))
    targets += [
        .target(
            name: "MacAdapters", dependencies: ["BugeyeCore"], path: "Sources/Mac/MacAdapters",
            swiftSettings: swift6),
        .executableTarget(
            name: "BugeyeApp",
            dependencies: ["BugeyeCore", "BugeyeFeatures", "MacAdapters"] + areaCores.map { .target(name: $0) },
            swiftSettings: swift6),
        .executableTarget(
            name: "BugeyeFixture", dependencies: ["BugeyeCore", "BugeyeTestSupport"], swiftSettings: swift6),
        .executableTarget(name: "BugeyeIconTool", swiftSettings: swift6),
        .testTarget(
            name: "MacAdaptersTests", dependencies: ["MacAdapters", "BugeyeTestSupport"], swiftSettings: swift6),
        .testTarget(name: "BugeyeAppTests", dependencies: ["BugeyeApp", "BugeyeTestSupport"], swiftSettings: swift6),
        .testTarget(name: "BugeyeIconToolTests", dependencies: ["BugeyeIconTool"], swiftSettings: swift6),
    ]
#endif

let package = Package(
    name: "Bugeye",
    platforms: [.macOS(.v26)],
    products: products,
    targets: targets
)
