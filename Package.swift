// swift-tools-version: 6.1

import PackageDescription

let package = Package(
    name: "FolioFold",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "FolioFoldCore", targets: ["FolioFoldCore"]),
        .executable(name: "FolioFold", targets: ["FolioFold"])
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.9.6")
    ],
    targets: [
        .target(name: "FolioFoldCore"),
        .executableTarget(
            name: "FolioFold",
            dependencies: [
                "FolioFoldCore",
                .product(name: "Sparkle", package: "Sparkle")
            ],
            resources: [.process("Resources")]
        ),
        .testTarget(name: "FolioFoldCoreTests", dependencies: ["FolioFoldCore"])
    ]
)
