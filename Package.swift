// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "swift-xc",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .executable(name: "xc", targets: ["xc"]),
        .library(name: "XCCore", targets: ["XCCore"])
    ],
    dependencies: [
        .package(url: "https://github.com/mgacy/swift-version-file-plugin.git", from: "0.2.0"),
        .package(url: "https://github.com/apple/swift-argument-parser", .upToNextMinor(from: "1.8.0"))
    ],
    targets: [
        .executableTarget(
            name: "xc",
            dependencies: [
                "XCCore",
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ]
        ),
        .target(
            name: "XCCore",
            dependencies: []
        ),
        .testTarget(
            name: "xcTests",
            dependencies: ["xc"]
        ),
        .testTarget(
            name: "XCCoreTests",
            dependencies: ["XCCore"],
            resources: [.process("Fixtures")]
        )
    ]
)
