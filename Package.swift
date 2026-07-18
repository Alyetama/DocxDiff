// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "DocxDiff",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "DocxDiffCore", targets: ["DocxDiffCore"]),
        .executable(name: "DocxDiff", targets: ["DocxDiff"])
    ],
    targets: [
        .target(name: "DocxDiffCore"),
        .executableTarget(name: "DocxDiff", dependencies: ["DocxDiffCore"]),
        .testTarget(name: "DocxDiffCoreTests", dependencies: ["DocxDiffCore"]),
        .testTarget(name: "DocxDiffUITests", dependencies: ["DocxDiff", "DocxDiffCore"])
    ],
    swiftLanguageVersions: [.v5]
)
