// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "TouchGate",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "TouchGate", targets: ["TouchGate"])],
    targets: [
        .target(name: "TouchGateCore"),
        .executableTarget(name: "TouchGate", dependencies: ["TouchGateCore"]),
        .testTarget(name: "TouchGateCoreTests", dependencies: ["TouchGateCore"])
    ]
)
