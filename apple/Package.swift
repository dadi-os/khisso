// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "DadiTunnel",
    platforms: [.macOS(.v14), .iOS("26.0")],
    products: [
        .library(name: "DadiTunnel", targets: ["DadiTunnel"]),
    ],
    targets: [
        .binaryTarget(name: "Dadi", path: "../build/Dadi.xcframework"),
        .target(
            name: "DadiTunnel",
            dependencies: ["Dadi"],
            linkerSettings: [.linkedLibrary("resolv")]
        ),
    ]
)
