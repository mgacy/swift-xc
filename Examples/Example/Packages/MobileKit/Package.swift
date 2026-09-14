// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "MobileKit",
    platforms: [
        .iOS(.v26)
    ],
    products: [
        .library(name: "MobileKit", targets: ["MobileKit"])
    ],
    dependencies: [
        .package(path: "../SharedKit")
    ],
    targets: [
        .target(
            name: "MobileKit",
            dependencies: [
                .product(name: "SharedKit", package: "SharedKit")
            ]
        ),
        .testTarget(name: "MobileKitTests", dependencies: ["MobileKit"])
    ],
    swiftLanguageModes: [.v6]
)
