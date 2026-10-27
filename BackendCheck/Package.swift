// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "BackendCheck",
    platforms: [.macOS(.v13)],
    targets: [
        .target(
            name: "EduExpose",
            path: "Sources/EduExpose"
        ),
        .testTarget(
            name: "EduExposeTests",
            dependencies: ["EduExpose"],
            path: "Tests/EduExposeTests"
        )
    ]
)
