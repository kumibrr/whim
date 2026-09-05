// swift-tools-version: 6.0

import PackageDescription

let productionSources = ["AppComposition/WhimCoreVersion.swift"]
let unitTestSources = ["AppComposition/WhimCoreVersion.test.swift"]
let integrationTestSources = ["AppComposition/WhimCoreVersion.integration.test.swift"]

let package = Package(
    name: "WhimCore",
    platforms: [.iOS(.v18), .watchOS(.v11), .macOS(.v15)],
    products: [.library(name: "WhimCore", targets: ["WhimCore"])],
    targets: [
        .target(
            name: "WhimCore",
            path: "Sources/WhimCore",
            exclude: unitTestSources + integrationTestSources,
            sources: productionSources
        ),
        .testTarget(
            name: "WhimCoreUnitTests",
            dependencies: ["WhimCore"],
            path: "Sources/WhimCore",
            exclude: productionSources + integrationTestSources,
            sources: unitTestSources
        ),
        .testTarget(
            name: "WhimCoreIntegrationTests",
            dependencies: ["WhimCore"],
            path: "Sources/WhimCore",
            exclude: productionSources + unitTestSources,
            sources: integrationTestSources
        ),
    ]
)
