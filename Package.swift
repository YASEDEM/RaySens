// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "RaySens",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "RaySens", targets: ["RaySens"])],
    targets: [.executableTarget(name: "RaySens")]
)
