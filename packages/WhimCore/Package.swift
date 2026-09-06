// swift-tools-version: 6.0

import PackageDescription

let productionSources = [
    "AppComposition/WhimCoreVersion.swift",
    "Delivery/Delivery.swift",
    "Delivery/DeliveryReducer.swift",
    "Delivery/RetryPolicy.swift",
    "Delivery/DeliveryTimeouts.swift",
    "Delivery/HTTPTransport.swift",
    "Delivery/URLSessionHTTPTransport.swift",
    "Delivery/DeliveryService.swift",
    "Delivery/InProcessDeliveryScheduler.swift",
    "Delivery/LocalNotificationAdapter.swift",
    "Maintenance/Clock.swift",
    "Delivery/Workflow.swift",
    "Notes/Note.swift",
    "Notes/WhimStore.swift",
    "Notes/DatabaseMigrator.swift",
    "Notes/AudioFileStore.swift",
    "Notes/FileProtection.swift",
    "Notes/SQLiteWhimStore.swift",
    "Recording/AudioRecorder.swift",
    "Recording/AVAudioRecorderAdapter.swift",
    "Recording/RecordingLimits.swift",
    "Recording/RecordingService.swift",
    "Recording/RecordingSessionID.swift",
    "Recovery/RecoveryScanner.swift",
    "Retention/RetentionPolicy.swift",
    "TitleEnrichment/Transcriber.swift",
    "TitleEnrichment/OnDeviceTranscriber.swift",
    "TitleEnrichment/TitleService.swift",
    "WebhookConfiguration/WebhookConfiguration.swift",
    "WebhookConfiguration/CredentialStore.swift",
    "WebhookConfiguration/KeychainCredentialStore.swift",
    "WebhookConfiguration/WebhookConfigurationService.swift",
    "WebhookConfiguration/ConfigurationTestService.swift",
    "WebhookConfiguration/WebhookValidator.swift",
    "WebhookConfiguration/WebhookRequestBuilder.swift",
]
let unitTestSources = [
    "AppComposition/WhimCoreVersion.test.swift",
    "Delivery/Delivery.test.swift",
    "Delivery/DeliveryReducer.test.swift",
    "Delivery/RetryPolicy.test.swift",
    "Delivery/Workflow.test.swift",
    "Delivery/DeliveryService.test.swift",
    "Notes/Note.test.swift",
    "Recording/AVAudioRecorderAdapter.test.swift",
    "Recording/RecordingService.test.swift",
    "TitleEnrichment/OnDeviceTranscriber.test.swift",
    "TitleEnrichment/TitleService.test.swift",
    "Retention/RetentionPolicy.test.swift",
    "WebhookConfiguration/WebhookConfiguration.test.swift",
    "WebhookConfiguration/WebhookValidator.test.swift",
    "WebhookConfiguration/ConfigurationTestService.test.swift",
    "WebhookConfiguration/WebhookRequestBuilder.test.swift",
]
let integrationTestSources = [
    "AppComposition/WhimCoreVersion.integration.test.swift",
    "Notes/SQLiteWhimStore.integration.test.swift",
    "Recovery/RecoveryScanner.integration.test.swift",
    "Recording/RecordingService.integration.test.swift",
    "WebhookConfiguration/KeychainCredentialStore.integration.test.swift",
    "WebhookConfiguration/WebhookRequestBuilder.integration.test.swift",
]
let fixtureResources = ["WebhookConfiguration/Fixtures"]

let package = Package(
    name: "WhimCore",
    platforms: [.iOS(.v18), .watchOS(.v11), .macOS(.v15)],
    products: [.library(name: "WhimCore", targets: ["WhimCore"])],
    dependencies: [.package(url: "https://github.com/groue/GRDB.swift.git", from: "7.10.0")],
    targets: [
        .target(
            name: "WhimCore",
            dependencies: [.product(name: "GRDB", package: "GRDB.swift")],
            path: "Sources/WhimCore",
            exclude: unitTestSources + integrationTestSources + fixtureResources,
            sources: productionSources
        ),
        .testTarget(
            name: "WhimCoreUnitTests",
            dependencies: ["WhimCore"],
            path: "Sources/WhimCore",
            exclude: productionSources + integrationTestSources + fixtureResources,
            sources: unitTestSources
        ),
        .testTarget(
            name: "WhimCoreIntegrationTests",
            dependencies: ["WhimCore"],
            path: "Sources/WhimCore",
            exclude: productionSources + unitTestSources,
            sources: integrationTestSources,
            resources: [.copy("WebhookConfiguration/Fixtures")]
        ),
    ]
)
