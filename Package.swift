// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "HeadshotGenerator",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "HeadshotGenerator", targets: ["HeadshotGenerator"]),
        .library(name: "HeadshotCore", targets: ["HeadshotCore"]),
    ],
    targets: [
        .target(name: "HeadshotCore"),
        .executableTarget(name: "HeadshotGenerator", dependencies: ["HeadshotCore"]),
        .testTarget(name: "HeadshotCoreTests", dependencies: ["HeadshotCore"]),
    ]
)
