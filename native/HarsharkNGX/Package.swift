// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "HarsharkCore",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "HarsharkCore", targets: ["HarsharkCore"]),
        .executable(name: "harsharkngx-mcp", targets: ["HarsharkMCP"]),
        .executable(name: "harshark-benchmark", targets: ["HarsharkBenchmark"])
    ],
    targets: [
        .target(name: "HarsharkCore", path: "HarsharkNGX/Core"),
        .executableTarget(name: "HarsharkMCP", dependencies: ["HarsharkCore"]),
        .executableTarget(name: "HarsharkBenchmark", dependencies: ["HarsharkCore"]),
        .testTarget(name: "HarsharkCoreTests", dependencies: ["HarsharkCore"])
    ]
)
