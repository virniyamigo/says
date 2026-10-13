// swift-tools-version: 6.0
import PackageDescription

var products: [Product] = [.library(name: "MyProgressCore", targets: ["MyProgressCore"])]
var targets: [Target] = [
    .target(name: "MyProgressCore"),
    .testTarget(name: "MyProgressCoreTests", dependencies: ["MyProgressCore"])
]
#if os(macOS)
products.append(.executable(name: "MyProgress", targets: ["MyProgress"]))
targets.append(.executableTarget(name: "MyProgress", dependencies: ["MyProgressCore"]))
#endif
let package = Package(
    name: "MyProgress",
    platforms: [.macOS(.v14)],
    products: products,
    targets: targets,
    swiftLanguageModes: [.v5]
)
