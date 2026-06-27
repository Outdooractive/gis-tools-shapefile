// swift-tools-version:6.1

import PackageDescription

let package = Package(
    name: "gis-tools-shapefile",
    platforms: [
        .iOS(.v15),
        .macOS(.v15),
        .tvOS(.v15),
        .watchOS(.v7),
    ],
    products: [
        .library(
            name: "GISToolsShapefile",
            targets: ["GISToolsShapefile"]),
    ],
    dependencies: [
        .package(url: "https://github.com/Outdooractive/gis-tools.git", from: "2.0.0"),
    ],
    targets: [
        .target(
            name: "GISToolsShapefile",
            dependencies: [
                .product(name: "GISTools", package: "gis-tools"),
            ]),
        .testTarget(
            name: "GISToolsShapefileTests",
            dependencies: ["GISToolsShapefile"],
            exclude: ["TestData"]),
    ]
)
