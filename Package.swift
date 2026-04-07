// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "CodexMeter",
    platforms: [
        .macOS("26.0")
    ],
    products: [
        .library(name: "CodexMeterCore", targets: ["CodexMeterCore"]),
        .executable(name: "CodexMeterApp", targets: ["CodexMeterApp"])
    ],
    targets: [
        .target(
            name: "CodexMeterCore"
        ),
        .executableTarget(
            name: "CodexMeterApp",
            dependencies: ["CodexMeterCore"]
        ),
        .testTarget(
            name: "CodexMeterCoreTests",
            dependencies: ["CodexMeterCore"]
        )
    ]
)
