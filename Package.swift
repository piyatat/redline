// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Redline",
    platforms: [
        .iOS(.v15),
        .macOS(.v13),
    ],
    products: [
        .library(name: "RedlineShared", targets: ["RedlineShared"]),
        .library(name: "RedlineServer", targets: ["RedlineServer"]),
        .executable(name: "redline", targets: ["RedlineCLI"]),
    ],
    targets: [
        .target(name: "RedlineShared"),
        .target(
            name: "RedlineServer",
            dependencies: ["RedlineShared"]
        ),
        .executableTarget(
            name: "RedlineCLI",
            dependencies: ["RedlineShared"]
        ),
        .testTarget(
            name: "RedlineSharedTests",
            dependencies: ["RedlineShared"]
        ),
    ]
)
