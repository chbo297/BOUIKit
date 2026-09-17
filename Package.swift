// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "BOUIKit",
    platforms: [
        .iOS(.v13),
        .macCatalyst(.v13),
        .macOS(.v12)
    ],
    products: [
        .library(name: "BOUIKit", targets: ["BOUIKit"])
    ],
    targets: [
        .target(name: "BOUIKit"),
        .testTarget(name: "BOUIKitTests", dependencies: ["BOUIKit"])
    ]
)
