// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CleanUp",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "CleanUp",
            path: "Sources/CleanUp",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
