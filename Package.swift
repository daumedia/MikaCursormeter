// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MikaCursormeter",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "MikaCursormeter", targets: ["MikaCursormeter"])
    ],
    targets: [
        .executableTarget(
            name: "MikaCursormeter",
            path: "Sources/MikaCursormeter",
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ]
        )
    ]
)
