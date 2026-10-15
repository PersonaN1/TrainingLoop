// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TrainingLoopCore",
    defaultLocalization: "en",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "TrainingLoopCore", targets: ["TrainingLoopCore"])
    ],
    targets: [
        .target(name: "TrainingLoopCore", resources: [.process("Exercises.xcstrings")]),
        .testTarget(name: "TrainingLoopCoreTests", dependencies: ["TrainingLoopCore"])
    ]
)
