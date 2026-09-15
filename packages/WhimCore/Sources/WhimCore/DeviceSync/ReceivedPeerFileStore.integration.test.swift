import Foundation
import XCTest
@testable import WhimCore

final class ReceivedPeerFileTests: XCTestCase {
    func testSystemFileIsOwnedWithReplayableMetadataBeforeCallbackReturns() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let ephemeral = root.appendingPathComponent("system.m4a")
        let fixture = Bundle.module.url(forResource: "configuration-test-fixture", withExtension: "m4a", subdirectory: "Fixtures")!
        try FileManager.default.copyItem(at: fixture, to: ephemeral)
        let envelope = ConnectivityEnvelope(payload: .noteMetadata(.init(id: NoteID(), recordingSessionID: RecordingSessionID(),
            title: "Owned file", titleSource: .timestamp, createdAt: Date(), duration: 1, source: .appleWatch,
            captureOutcome: .completed, requiresReview: false)))
        let inbox = try ReceivedPeerFileStore(root: root.appendingPathComponent("Received"))
        let owned = try inbox.takeOwnership(of: ephemeral, metadata: envelope.encoded())
        XCTAssertFalse(FileManager.default.fileExists(atPath: ephemeral.path))
        let reopened = try ReceivedPeerFileStore(root: root.appendingPathComponent("Received"))
        let replay = try reopened.pending()
        XCTAssertEqual(replay.count, 1)
        XCTAssertEqual(replay.first?.url.resolvingSymlinksInPath().path, owned.resolvingSymlinksInPath().path)
        XCTAssertEqual(try replay.first.map { try ConnectivityEnvelope.decode($0.metadata) }, envelope)
        XCTAssertEqual(try Data(contentsOf: owned), try Data(contentsOf: fixture))
        try reopened.complete(owned)
        XCTAssertTrue(try reopened.pending().isEmpty)
    }
}
