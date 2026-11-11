// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "FootballKit",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "FootballPhysics", targets: ["FootballPhysics"]),
        .library(name: "FootballGame", targets: ["FootballGame"]),
        .library(name: "FootballData", targets: ["FootballData"]),
        .library(name: "FootballModes", targets: ["FootballModes"]),
        .library(name: "FootballInput", targets: ["FootballInput"]),
        .library(name: "FootballAudio", targets: ["FootballAudio"]),
    ],
    targets: [
        // Pure-Swift, no rendering dependencies: deterministic and unit-testable.
        .target(name: "FootballPhysics"),
        .target(name: "FootballGame", dependencies: ["FootballPhysics"]),
        .target(name: "FootballData", dependencies: ["FootballGame", "FootballPhysics"]),
        .target(name: "FootballModes", dependencies: ["FootballData", "FootballGame"]),
        .target(name: "FootballInput", dependencies: ["FootballGame", "FootballPhysics"]),
        .target(name: "FootballAudio"),
        // Command-line tools (synthetic tracking export for tactical validation).
        .executableTarget(name: "SimExport", dependencies: ["FootballGame", "FootballPhysics"]),
        .testTarget(name: "FootballPhysicsTests", dependencies: ["FootballPhysics"]),
        .testTarget(name: "FootballDataTests", dependencies: ["FootballData", "FootballGame"], resources: [.copy("clubs_fixture.json")]),
        .testTarget(name: "FootballModesTests", dependencies: ["FootballModes", "FootballData", "FootballGame"], resources: [.copy("clubs_fixture.json")]),
        .testTarget(name: "FootballAudioTests", dependencies: ["FootballAudio"]),
        .testTarget(name: "FootballInputTests", dependencies: ["FootballInput", "FootballGame", "FootballPhysics"]),
        .testTarget(name: "FootballGameTests", dependencies: ["FootballGame", "FootballPhysics"]),
    ],
    swiftLanguageModes: [.v5]
)
