// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "DualMonitorRecorder",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "DualMonitorRecorder", targets: ["DualMonitorRecorder"]),
        .executable(name: "dualrec", targets: ["DualRecorderCLI"])
    ],
    targets: [
        .executableTarget(
            name: "DualMonitorRecorder",
            path: "Sources/DualMonitorRecorder"
        ),
        .executableTarget(
            name: "DualRecorderCLI",
            path: "Sources/DualRecorderCLI"
        ),
        .testTarget(
            name: "DualMonitorRecorderTests",
            dependencies: ["DualMonitorRecorder"],
            path: "Tests/DualMonitorRecorderTests"
        )
    ]
)
