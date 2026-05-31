// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "LiveLoupe",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "LiveLoupe", targets: ["LiveLoupe"])
    ],
    targets: [
        .executableTarget(
            name: "LiveLoupe",
            path: "Sources/LiveLoupe"
        )
    ]
)
