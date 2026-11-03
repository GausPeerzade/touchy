// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Touchy",
    platforms: [.macOS(.v13)],
    targets: [
        .target(name: "CPrivate", linkerSettings: [.linkedFramework("CoreGraphics")]),
        .target(name: "TouchyCore", dependencies: ["CPrivate"]),
        .executableTarget(name: "Touchy", dependencies: ["CPrivate", "TouchyCore"]),
        .testTarget(name: "TouchyCoreTests", dependencies: ["TouchyCore", "CPrivate"]),
    ]
)
