// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "KeynoteCompanion",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "KeynoteCompanion", targets: ["KeynoteCompanion"]),
        .library(name: "KeynoteCompanionCore", targets: ["KeynoteCompanionCore"]),
    ],
    targets: [
        // Pure Foundation: notes parsing, wire protocol, trigger rules. Testable anywhere.
        .target(name: "KeynoteCompanionCore"),
        // The menu-bar app: Keynote bridge, TCP server, SwiftUI.
        .executableTarget(
            name: "KeynoteCompanion",
            dependencies: ["KeynoteCompanionCore"]
        ),
        .testTarget(
            name: "KeynoteCompanionCoreTests",
            dependencies: ["KeynoteCompanionCore"]
        ),
    ]
)
