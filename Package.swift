// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "Threadmark",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "ThreadmarkCore", targets: ["ThreadmarkCore"]),
        .executable(name: "Threadmark", targets: ["Threadmark"]),
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.9.6"),
    ],
    targets: [
        .target(name: "ThreadmarkCore"),
        .executableTarget(
            name: "Threadmark",
            dependencies: [
                "ThreadmarkCore",
                .product(name: "Sparkle", package: "Sparkle"),
            ],
            linkerSettings: [
                .unsafeFlags([
                    "-Xlinker", "-rpath",
                    "-Xlinker", "@executable_path/../Frameworks",
                ]),
            ]
        ),
        .testTarget(
            name: "ThreadmarkCoreTests",
            dependencies: ["ThreadmarkCore"]
        ),
    ]
)
