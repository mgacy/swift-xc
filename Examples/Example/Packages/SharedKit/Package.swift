// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "SharedKit",
    platforms: [
        .iOS(.v26),
        .macOS(.v26)
    ],
    products: [
        .library(name: "SharedKit", targets: ["SharedKit"])
    ],
    targets: [
        .target(name: "SharedKit"),
        .testTarget(name: "SharedKitTests", dependencies: ["SharedKit"]),
        .testTarget(name: "SharedKitEnvironmentTests", dependencies: ["SharedKit"])
    ],
    swiftLanguageModes: [.v6]
)
