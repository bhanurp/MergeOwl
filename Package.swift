// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "PRPulse",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(
            name: "PRPulseApp",
            targets: ["PRPulseApp"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.0")
    ],
    targets: [
        .executableTarget(
            name: "PRPulseApp",
            dependencies: [.product(name: "Sparkle", package: "Sparkle")],
            exclude: ["UI/README.md"],
            resources: [
                .process("Resources")
            ],
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency")
            ],
            linkerSettings: [
                .unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])
            ]
        ),
        .testTarget(
            name: "PRPulseAppTests",
            dependencies: ["PRPulseApp"]
        )
    ]
)
