// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "Pingers",
    platforms: [
        .macOS(.v11) // Big Sur
    ],
    products: [
        .library(
            name: "PingersLib",
            targets: ["PingersLib"]
        ),
    ],
    targets: [
        .target(
            name: "PingersLib"
        ),
        .executableTarget(
            name: "Pingers",
            dependencies: ["PingersLib"]
        ),
        .testTarget(
            name: "PingersTests",
            dependencies: ["PingersLib"]
        ),
    ]
)
