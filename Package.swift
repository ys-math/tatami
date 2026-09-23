// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Tatami",
    platforms: [.macOS(.v26)],
    products: [
        .executable(name: "Tatami", targets: ["Tatami"]),
        .library(name: "TatamiCore", targets: ["TatamiCore"]),
    ],
    targets: [
        .target(name: "TatamiCore"),
        .executableTarget(
            name: "Tatami",
            dependencies: ["TatamiCore"]
        ),
        .testTarget(name: "TatamiCoreTests", dependencies: ["TatamiCore"]),
        .testTarget(name: "TatamiTests", dependencies: ["Tatami", "TatamiCore"]),
    ]
)
