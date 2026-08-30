// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "P2PMacTester",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "P2PMacTester", targets: ["P2PMacTester"])
    ],
    targets: [
        .executableTarget(
            name: "P2PMacTester"
        )
    ]
)
