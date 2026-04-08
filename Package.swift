// swift-tools-version: 5.8
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "TopCutout",
    platforms: [.iOS(.v13)],
    products: [
        .library(
            name: "TopCutout",
            targets: ["TopCutout"]
        ),
    ],
    targets: [
        .target(
            name: "TopCutout",
            path: "Sources/TopCutout"
        ),
    ]
)
