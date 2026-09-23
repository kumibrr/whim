// swift-tools-version: 6.0
import PackageDescription
import Foundation

let modelSources = ["timeline/TimelineFormat.swift", "app-composition/IPhoneModel.swift", "app-composition/IPhoneError.swift", "note-detail/NoteDetailModel.swift", "webhook-configuration/WebhookEditor.swift"]
let unitSources = ["timeline/TimelineFormat.test.swift", "app-composition/IPhoneError.test.swift"]
let integrationSources = ["app-composition/IPhoneModel.integration.test.swift", "app-composition/IPhoneModel.test-support.swift", "note-detail/NoteDetailModel.integration.test.swift", "webhook-configuration/WebhookEditor.integration.test.swift"]
let sourceRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("src/iphone")
let allSources = (FileManager.default.enumerator(atPath: sourceRoot.path)?.allObjects as? [String] ?? []).filter {
    var directory: ObjCBool = false
    return FileManager.default.fileExists(atPath: sourceRoot.appendingPathComponent($0).path, isDirectory: &directory) && !directory.boolValue
}
let package = Package(
    name: "WhimIPhone",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [.library(name: "WhimIPhone", targets: ["WhimIPhone"])],
    dependencies: [.package(path: "packages/WhimCore")],
    targets: [
        .target(name: "WhimIPhone", dependencies: [.product(name: "WhimCore", package: "WhimCore")],
                path: "src/iphone", exclude: allSources.filter { !modelSources.contains($0) }, sources: modelSources),
        .testTarget(name: "WhimIPhoneUnitTests", dependencies: ["WhimIPhone"],
                    path: "src/iphone", exclude: allSources.filter { !unitSources.contains($0) }, sources: unitSources),
        .testTarget(name: "WhimIPhoneIntegrationTests", dependencies: ["WhimIPhone", .product(name: "WhimCore", package: "WhimCore")], path: "src/iphone", exclude: allSources.filter { !integrationSources.contains($0) && !$0.hasPrefix("app-composition/Fixtures/") }, sources: integrationSources, resources: [.copy("app-composition/Fixtures")]),
    ])
