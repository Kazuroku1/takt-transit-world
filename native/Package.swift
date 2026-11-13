// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "TaktCore",
    platforms: [.iOS(.v17), .macOS(.v13)],
    products: [.library(name: "TaktCore", targets: ["TaktCore"])],
    targets: [
        .target(name: "TaktCore"),
        .testTarget(name: "TaktCoreTests", dependencies: ["TaktCore"])
    ]
)
