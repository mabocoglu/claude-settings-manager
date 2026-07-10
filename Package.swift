// swift-tools-version: 6.3
import PackageDescription

let package = Package(
    name: "ClaudeSettingsManager",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "ClaudeSettingsManager", targets: ["ClaudeSettingsManager"])
    ],
    targets: [
        .executableTarget(name: "ClaudeSettingsManager")
    ],
    swiftLanguageModes: [.v6]
)
