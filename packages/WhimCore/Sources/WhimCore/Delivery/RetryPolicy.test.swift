import Foundation
import XCTest
@testable import WhimCore

final class RetryPolicyTests: XCTestCase {
    func testClassifiesRetryableFailures() {
        XCTAssertEqual(RetryPolicy.classification(for: .network), .retryable)
        for statusCode in [408, 425, 429, 500, 503, 599] {
            XCTAssertEqual(RetryPolicy.classification(for: .httpStatus(statusCode)), .retryable)
        }
    }

    func testClassifiesOtherClientErrorsAsPermanent() {
        for statusCode in [400, 401, 403, 404, 422, 499, 600] {
            XCTAssertEqual(RetryPolicy.classification(for: .httpStatus(statusCode)), .permanent)
        }
    }

    func testFiveHundredRangeBoundariesAreRetryable() {
        XCTAssertEqual(RetryPolicy.classification(for: .httpStatus(500)), .retryable)
        XCTAssertEqual(RetryPolicy.classification(for: .httpStatus(599)), .retryable)
    }

    func testReturnsEarliestEligibilityAndStopsAfterThreeFailures() {
        let now = Date(timeIntervalSince1970: 1_000)

        XCTAssertEqual(RetryPolicy.nextEligibility(after: 0, now: now, retryAfter: nil), now)
        XCTAssertEqual(
            RetryPolicy.nextEligibility(after: 1, now: now, retryAfter: nil),
            now.addingTimeInterval(60)
        )
        XCTAssertEqual(
            RetryPolicy.nextEligibility(after: 2, now: now, retryAfter: nil),
            now.addingTimeInterval(900)
        )
        XCTAssertNil(RetryPolicy.nextEligibility(after: 3, now: now, retryAfter: nil))
        XCTAssertNil(RetryPolicy.nextEligibility(after: -1, now: now, retryAfter: nil))
    }

    func testRetryAfterCanOnlyMoveEligibilityLater() {
        let now = Date(timeIntervalSince1970: 1_000)
        let retryAfter = now.addingTimeInterval(120)

        XCTAssertEqual(
            RetryPolicy.nextEligibility(after: 1, now: now, retryAfter: retryAfter),
            retryAfter
        )
    }
}
