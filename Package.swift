// swift-tools-version: 5.10
import PackageDescription
let package = Package(name: "LocalDictation", platforms: [.macOS(.v14)], products: [
    .executable(name: "LocalDictation", targets: ["LocalDictation"]),
    .executable(name: "dictation-check", targets: ["DictationCheck"])
], dependencies: [.package(url: "https://github.com/argmaxinc/argmax-oss-swift.git", exact: "1.1.0")], targets: [
    .target(name: "DictationCore"),
    .target(name: "DictationSpeech", dependencies: ["DictationCore", .product(name: "WhisperKit", package: "argmax-oss-swift")]),
    .executableTarget(name: "LocalDictation", dependencies: ["DictationCore", "DictationSpeech"]),
    .executableTarget(name: "DictationCheck", dependencies: ["DictationCore", "DictationSpeech"]),
    .testTarget(name: "DictationCoreTests", dependencies: ["DictationCore"]),
    .testTarget(name: "DictationSpeechTests", dependencies: ["DictationSpeech"])
])
