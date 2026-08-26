// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "Threadmark",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "ThreadmarkCore", targets: ["ThreadmarkCore"]),
        .executable(name: "Threadmark", targets: ["Threadmark"]),
    ],
    targets: [
        .target(name: "ThreadmarkCore"),
        .executableTarget(
            name: "Threadmark",
            dependencies: ["ThreadmarkCore"]
        ),
        .testTarget(
            name: "ThreadmarkCoreTests",
            dependencies: ["ThreadmarkCore"]
        ),
    ]
)
