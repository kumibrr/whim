// swift-tools-version: 6.0

import PackageDescription

let productionSources = [
    "AppComposition/WhimCoreVersion.swift",
    "Delivery/Delivery.swift",
    "Delivery/DeliveryReducer.swift",
    "Delivery/RetryPolicy.swift",
    "Delivery/Workflow.swift",
    "Notes/Note.swift",
    "Notes/WhimStore.swift",
    "Recording/RecordingSessionID.swift",
    "Retention/RetentionPolicy.swift",
    "WebhookConfiguration/WebhookConfiguration.swift",
]
let unitTestSources = [
    "AppComposition/WhimCoreVersion.test.swift",
    "Delivery/Delivery.test.swift",
    "Delivery/DeliveryReducer.test.swift",
    "Delivery/RetryPolicy.test.swift",
    "Delivery/Workflow.test.swift",
    "Notes/Note.test.swift",
    "Retention/RetentionPolicy.test.swift",
    "WebhookConfiguration/WebhookConfiguration.test.swift",
]
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
