// swift-tools-version:5.9
import PackageDescription

// Built with SwiftPM rather than an Xcode project so that the Command Line
// Tools alone are enough — `swift build` and `swift test` ship with them.
// scripts/build-app.sh drives this and then assembles the .app bundle.
let package = Package(
    name: "Transcribe",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "TranscribeCore", targets: ["TranscribeCore"]),
        .executable(name: "transcribe", targets: ["TranscribeCLI"]),
        // Not "Transcribe": macOS filesystems are case-insensitive, so a product
        // named that would be the same path as the `transcribe` CLI above and one
        // would silently overwrite the other. build-app.sh renames it to
        // Transcribe inside the bundle, where it is the only executable.
        .executable(name: "TranscribeApp", targets: ["TranscribeApp"]),
    ],
    targets: [
        // The whole pipeline. Both front ends depend on this and nothing else,
        // so they cannot drift apart, and its public surface is deliberately
        // small: everything the app does not need stays internal.
        .target(name: "TranscribeCore", path: "Sources/Core"),
        .executableTarget(name: "TranscribeCLI", dependencies: ["TranscribeCore"], path: "Sources/CLI"),
        .executableTarget(name: "TranscribeApp", dependencies: ["TranscribeCore"], path: "Sources/App"),
        // `@testable` keeps the internals reachable from tests without widening
        // the public API to suit them.
        .testTarget(name: "TranscribeCoreTests", dependencies: ["TranscribeCore"],
                    path: "Tests/TranscribeCoreTests"),
    ]
)
