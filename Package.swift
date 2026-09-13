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
    targets: [
        .executableTarget(
            name: "PRPulseApp",
            resources: [
                .process("Resources")
            ],
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency")
            ]
        ),
        .testTarget(
            name: "PRPulseAppTests",
            dependencies: ["PRPulseApp"]
        )
    ]
)
