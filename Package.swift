// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Email2Claude",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "Email2ClaudeCore"),
        .executableTarget(name: "Email2Claude", dependencies: ["Email2ClaudeCore"]),
        .testTarget(name: "Email2ClaudeCoreTests", dependencies: ["Email2ClaudeCore"]),
    ]
)
