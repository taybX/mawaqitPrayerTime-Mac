// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MawaqitKit",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "MawaqitKit", targets: ["MawaqitKit"]),
    ],
    targets: [
        .target(name: "MawaqitKit"),
        .testTarget(name: "MawaqitKitTests", dependencies: ["MawaqitKit"]),
    ]
)
