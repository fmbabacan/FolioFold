// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "FolioFold",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "FolioFoldCore", targets: ["FolioFoldCore"]),
        .executable(name: "FolioFold", targets: ["FolioFold"])
    ],
    targets: [
        .target(name: "FolioFoldCore"),
        .executableTarget(
            name: "FolioFold",
            dependencies: ["FolioFoldCore"],
            resources: [.process("Resources")]
        ),
        .testTarget(name: "FolioFoldCoreTests", dependencies: ["FolioFoldCore"])
    ]
)
