// swift-tools-version:5.5
import PackageDescription

let package = Package(
    name: "ExoGridChart",
    platforms: [
        .macOS(.v10_15),
        .iOS(.v13),
    ],
    products: [
        .library(name: "ExoGridChart", targets: ["ExoGridChart"]),
    ],
    dependencies: [],
    targets: [
        .target(
            name: "ExoGridChart",
            dependencies: ["CExoGridChart"],
            path: "Sources/ExoGridChart"
        ),
        .target(
            name: "CExoGridChart",
            path: "Sources/CExoGridChart",
            publicHeadersPath: "."
        ),
    ]
)
