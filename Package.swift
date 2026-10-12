// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "Iris",
    platforms: [.macOS(.v14)],
    targets: [
        .target(
            name: "CUVC",
            linkerSettings: [
                .linkedFramework("IOKit"),
                .linkedFramework("CoreFoundation"),
            ]
        ),
        .executableTarget(
            name: "Iris",
            dependencies: ["CUVC"]
        ),
    ]
)
