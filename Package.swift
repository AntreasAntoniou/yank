// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Yank",
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        .executableTarget(
            name: "Yank",
            path: "Sources/Yank",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("SwiftUI"),
                .linkedFramework("Carbon"),
                .linkedFramework("UniformTypeIdentifiers"),
                .linkedLibrary("sqlite3")
            ]
        ),
        .testTarget(
            name: "YankTests",
            dependencies: ["Yank"],
            path: "Tests/YankTests",
            resources: [.copy("Fixtures")]
        )
    ]
)
