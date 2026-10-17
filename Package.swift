// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ZhuyinEngine",
    defaultLocalization: "zh-Hant",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(
            name: "ZhuyinEngine",
            targets: ["ZhuyinEngine"]
        ),
        .executable(
            name: "ZhuyinCLI",
            targets: ["ZhuyinCLI"]
        ),
        .executable(
            name: "HaoZhuyin",
            targets: ["HaoZhuyin"]
        )
    ],
    targets: [
        .target(
            name: "ZhuyinEngine",
            dependencies: [],
            path: "Sources/ZhuyinEngine",
            resources: [.process("Resources")]
        ),
        .executableTarget(
            name: "ZhuyinCLI",
            dependencies: ["ZhuyinEngine"],
            path: "Sources/ZhuyinCLI"
        ),
        .executableTarget(
            name: "HaoZhuyin",
            dependencies: ["ZhuyinEngine"],
            path: "Sources/HaoZhuyin",
            exclude: ["Resources"]
        ),
        .testTarget(
            name: "ZhuyinEngineTests",
            dependencies: ["ZhuyinEngine"],
            path: "Tests/ZhuyinEngineTests"
        )
    ]
)
