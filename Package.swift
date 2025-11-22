// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "PingMenubar",
    platforms: [
        .macOS(.v11) // Big Sur
    ],
    products: [
        .library(
            name: "PingMenubarLib",
            targets: ["PingMenubarLib"]
        ),
    ],
    targets: [
        .target(
            name: "PingMenubarLib"
        ),
        .executableTarget(
            name: "PingMenubar",
            dependencies: ["PingMenubarLib"]
        ),
        .testTarget(
            name: "PingMenubarTests",
            dependencies: ["PingMenubarLib"]
        ),
    ]
)
