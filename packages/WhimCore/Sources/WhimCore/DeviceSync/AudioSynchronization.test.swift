import Foundation
import XCTest
import WhimCore

final class AudioSynchronizationTests: XCTestCase {
    func testLegacyAndFutureFailureMetadataRemainLoadable() throws {
        let decoder = JSONDecoder()
        let legacy = try decoder.decode(AudioSynchronization.self, from: Data(#"{"status":"waiting","transferCount":1}"#.utf8))
        XCTAssertNil(legacy.lastFailure)
        let future = try decoder.decode(AudioSynchronization.self, from: Data(#"{"status":"failed","transferCount":3,"lastFailure":{"reason":"futureFailure","observedAt":1}}"#.utf8))
        XCTAssertEqual(future.lastFailure?.reason, "unknown")
        let absent = try decoder.decode(AudioTransferUnavailable.self,
            from: JSONEncoder().encode(AudioTransferUnavailable(noteID: NoteID())))
        XCTAssertNil(absent.reason)
        let retry = try decoder.decode(AudioSynchronizationRetry.self,
            from: Data(#"{"id":"01000000-0000-0000-0000-000000000001","startedAt":1,"outcome":"failed"}"#.utf8))
        XCTAssertNil(retry.failure)
        XCTAssertNil(retry.completedAt)
    }
    func testUnknownPeerCauseAndFailureCannotRetainArbitraryText() throws {
        let id = NoteID()
        let unavailable = AudioTransferUnavailable(noteID: id, reason: "/private/secret")
        XCTAssertNil(unavailable.reason)
        let encoded = try JSONEncoder().encode(AudioTransferUnavailable(noteID: id, reason: "missingAudio"))
        var future = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        future["reason"] = "futureSourceReason"
        let decoded = try JSONDecoder().decode(AudioTransferUnavailable.self, from: JSONSerialization.data(withJSONObject: future))
        XCTAssertNil(decoded.reason)
        let failure = AudioSynchronizationFailure(reason: "https://secret.invalid/audio", observedAt: Date())
        XCTAssertEqual(failure.reason, "unknown")
        XCTAssertFalse(String(decoding: try JSONEncoder().encode(failure), as: UTF8.self).contains("secret"))
    }
}
