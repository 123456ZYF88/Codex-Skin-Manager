// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "CodexSkinManager",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "CodexSkinManager", targets: ["CodexSkinManager"]),
    ],
    targets: [
        .target(name: "CodexSkinManagerCore"),
        .executableTarget(name: "CodexSkinManager", dependencies: ["CodexSkinManagerCore"]),
        .executableTarget(
            name: "CodexSkinManagerTests",
            dependencies: ["CodexSkinManagerCore"],
            path: "Tests/CodexSkinManagerTests"
        ),
    ],
    swiftLanguageModes: [.v5]
)
