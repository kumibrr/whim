import CryptoKit
import Foundation
import XCTest
@testable import WhimCore

final class WebhookContractTests: XCTestCase {
    private let noteID = NoteID(rawValue: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!)
    private let attemptID = AttemptID(rawValue: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!)

    // Break: signing fields are reordered, padded, or separated differently.
    func testSigningInputUsesExactContractOrder() {
        XCTAssertEqual(WebhookSigner.input(timestamp: 1_788_553_200, noteID: noteID, attemptID: attemptID,
            metadataSHA256: "meta", audioSHA256: "audio"),
            "v1\n1788553200\n11111111-1111-1111-1111-111111111111\n22222222-2222-2222-2222-222222222222\nmeta\naudio")
    }

    // Break: metadata encoding becomes unstable or stops matching the exact documented schema.
    func testMetadataBytesAreStableUTF8JSON() throws {
        let metadata = WebhookMetadata(event: "note.created", noteID: noteID, attemptID: attemptID,
            createdAt: Date(timeIntervalSince1970: 1_788_553_200), durationMilliseconds: 42_000,
            source: .iphone, title: "Idea", titleSource: .transcription, captureOutcome: .completed,
            workflowID: "default", audioSHA256: "abc", audioSizeBytes: 123, appVersion: "1.0.0", appBuild: "1")
        let bytes = try WebhookJSON.encode(metadata)
        XCTAssertEqual(String(decoding: bytes, as: UTF8.self),
            #"{"app":{"build":"1","version":"1.0.0"},"attempt_id":"22222222-2222-2222-2222-222222222222","audio":{"sha256":"abc","size_bytes":123},"capture_outcome":"completed","created_at":"2026-09-04T20:20:00.000Z","duration_ms":42000,"event":"note.created","note_id":"11111111-1111-1111-1111-111111111111","schema_version":1,"source":"iphone","title":"Idea","title_source":"transcription","workflow_id":"default"}"#)
        XCTAssertEqual(WebhookDigest.sha256(Data("abc".utf8)), "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    }

    // Break: a secret is interpolated into a signer error description.
    func testConfigurationAndContractDescriptionsDoNotRevealSecrets() {
        let input = WebhookConfigurationInput(endpoint: "https://example.com/?key=URLSECRET", bearerToken: "TOKEN",
            hmacSecret: "HMAC", customHeaders: [.init(name: "X-Key", value: "HEADERSECRET", isSecret: true)])
        XCTAssertFalse(String(describing: input).contains("URLSECRET"))
        XCTAssertFalse(String(describing: input).contains("TOKEN"))
        XCTAssertFalse(String(describing: input).contains("HMAC"))
        XCTAssertFalse(String(describing: input).contains("HEADERSECRET"))
    }

    // Break: URLSession accumulates a hostile response body in memory before truncating it.
    func testTransportAccumulatorDiscardsBytesBeyondExcerptLimit() {
        var accumulator = BoundedResponseAccumulator(limit: DeliveryTimeouts.maximumErrorExcerptBytes)
        accumulator.append(Data(repeating: 0x78, count: DeliveryTimeouts.maximumErrorExcerptBytes * 4))
        XCTAssertEqual(accumulator.data.count, DeliveryTimeouts.maximumErrorExcerptBytes)
        XCTAssertEqual(accumulator.totalBytesReceived, DeliveryTimeouts.maximumErrorExcerptBytes * 4)
    }
}
