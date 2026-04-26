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
    dependencies: [
        .package(url: "https://github.com/getsentry/sentry-cocoa.git", exact: "8.58.0")
    ],
    targets: [
        .target(
            name: "CodexMeterCore"
        ),
        .executableTarget(
            name: "CodexMeterApp",
            dependencies: [
                "CodexMeterCore",
                .product(name: "Sentry", package: "sentry-cocoa")
            ],
            exclude: ["AppIcon.icon"],
            resources: [
                .process("Assets.xcassets")
            ]
        ),
        .testTarget(
            name: "CodexMeterCoreTests",
            dependencies: ["CodexMeterCore"]
        ),
        .testTarget(
            name: "CodexMeterAppTests",
            dependencies: ["CodexMeterApp", "CodexMeterCore"]
        )
    ]
)
