// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "T3MenuBar",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "T3MenuBarCore", targets: ["T3MenuBarCore"]),
        .executable(name: "T3MenuBar", targets: ["T3MenuBar"]),
    ],
    targets: [
        .target(name: "T3MenuBarCore"),
        .executableTarget(
            name: "T3MenuBar",
            dependencies: ["T3MenuBarCore"]
        ),
        .testTarget(
            name: "T3MenuBarCoreTests",
            dependencies: ["T3MenuBarCore"]
        ),
    ]
)
