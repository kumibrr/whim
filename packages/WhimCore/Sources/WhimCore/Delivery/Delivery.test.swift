import Foundation
import XCTest
@testable import WhimCore

final class DeliveryTests: XCTestCase {
    func testAttemptRetainsOnlySanitizedEndpointComponents() throws {
        let endpoint = try XCTUnwrap(
            SanitizedEndpoint(url: URL(string: "https://example.com:8443/whim?token=secret#fragment")!)
        )
        let attempt = Attempt(
            noteID: NoteID(),
            configurationRevisionID: ConfigurationRevisionID(),
            device: .iphone,
            endpoint: endpoint,
            startedAt: Date(timeIntervalSince1970: 1_000)
        )

        XCTAssertEqual(attempt.endpoint.scheme, "https")
        XCTAssertEqual(attempt.endpoint.host, "example.com")
        XCTAssertEqual(attempt.endpoint.port, 8443)
        XCTAssertEqual(attempt.endpoint.path, "/whim")
    }

    func testFailureRetainsRetryMetadataForPersistence() {
        let retryAfter = Date(timeIntervalSince1970: 2_000)
        let attempt = Attempt(
            noteID: NoteID(),
            configurationRevisionID: ConfigurationRevisionID(),
            device: .iphone,
            endpoint: SanitizedEndpoint(scheme: "https", host: "example.com", path: "/whim"),
            startedAt: Date(timeIntervalSince1970: 1_000)
        )
        let failure = AttemptFailure(
            attempt: attempt,
            failedAt: Date(timeIntervalSince1970: 1_500),
            reason: .httpStatus(429),
            retryAfter: retryAfter,
            responseExcerpt: "Please retry later"
        )

        XCTAssertEqual(failure.retryAfter, retryAfter)
        XCTAssertEqual(failure.responseExcerpt, "Please retry later")
    }

    func testDeliveryStatusRawValuesAreStable() {
        XCTAssertEqual(DeliveryStatus.setupRequired.rawValue, "setup_required")
        XCTAssertEqual(DeliveryStatus.queued.rawValue, "queued")
        XCTAssertEqual(DeliveryStatus.sending.rawValue, "sending")
        XCTAssertEqual(DeliveryStatus.sent.rawValue, "sent")
        XCTAssertEqual(DeliveryStatus.failed.rawValue, "failed")
    }
}
