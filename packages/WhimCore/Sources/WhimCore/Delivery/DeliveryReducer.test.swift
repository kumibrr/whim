import Foundation
import XCTest
@testable import WhimCore

final class DeliveryReducerTests: XCTestCase {
    private let noteID = NoteID(rawValue: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!)
    private let revisionID = ConfigurationRevisionID(
        rawValue: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
    )
    private let now = Date(timeIntervalSince1970: 1_000)

    func testProjectsSetupQueuedSendingExhaustedPermanentAndSentStates() {
        XCTAssertEqual(Delivery.pending.status, .setupRequired)

        var delivery = DeliveryReducer.reduce(
            .pending,
            event: .configurationAvailabilityChanged(true)
        )
        delivery = DeliveryReducer.reduce(delivery, event: .connectivityChanged(false))
        delivery = DeliveryReducer.reduce(delivery, event: .leaseChanged(false))
        XCTAssertEqual(delivery.status, .queued)

        let activeAttempt = attempt(number: 1, device: .iphone)
        delivery = DeliveryReducer.reduce(delivery, event: .attemptStarted(activeAttempt))
        XCTAssertEqual(delivery.status, .sending)

        delivery = configuredDelivery()
        for number in 1...RetryPolicy.maximumFailedAttempts {
            delivery = DeliveryReducer.reduce(
                delivery,
                event: .attemptFailed(failure(number: number, reason: .network))
            )
        }
        XCTAssertEqual(delivery.status, .failed)

        delivery = DeliveryReducer.reduce(
            configuredDelivery(),
            event: .attemptFailed(failure(number: 4, reason: .httpStatus(400)))
        )
        XCTAssertEqual(delivery.status, .failed)

        delivery = DeliveryReducer.reduce(delivery, event: .receipt(receipt(number: 5)))
        XCTAssertEqual(delivery.status, .sent)
    }

    func testReceiptIsAbsorbingWhenLaterWatchFailureArrives() {
        let firstReceipt = receipt(number: 1)
        let sent = DeliveryReducer.reduce(configuredDelivery(), event: .receipt(firstReceipt))
        let afterFailure = DeliveryReducer.reduce(
            sent,
            event: .attemptFailed(failure(number: 2, device: .appleWatch, reason: .network))
        )

        XCTAssertEqual(afterFailure.status, .sent)
        XCTAssertEqual(afterFailure.receipt?.attemptID, firstReceipt.attemptID)
        XCTAssertEqual(afterFailure.receipt?.noteID, noteID)
    }

    func testIPhoneReceiptWinsWhenItArrivesAfterWatchFailureForSameNote() {
        let failed = DeliveryReducer.reduce(
            configuredDelivery(),
            event: .attemptFailed(failure(number: 1, device: .appleWatch, reason: .network))
        )
        let iphoneReceipt = receipt(number: 2)
        let sent = DeliveryReducer.reduce(failed, event: .receipt(iphoneReceipt))

        XCTAssertEqual(sent.status, .sent)
        XCTAssertEqual(sent.receipt, iphoneReceipt)
        XCTAssertEqual(sent.receipt?.noteID, noteID)
    }

    func testPreservesFirstReceiptWhenAnotherSuccessArrives() {
        let firstReceipt = receipt(number: 1)
        var delivery = DeliveryReducer.reduce(configuredDelivery(), event: .receipt(firstReceipt))
        delivery = DeliveryReducer.reduce(delivery, event: .receipt(receipt(number: 2)))

        XCTAssertEqual(delivery.receipt, firstReceipt)
    }

    func testLateAttemptStartCannotResurrectAnAlreadyFailedAttempt() {
        let failedAttempt = failure(number: 1, reason: .network)
        var delivery = DeliveryReducer.reduce(
            configuredDelivery(),
            event: .attemptFailed(failedAttempt)
        )
        delivery = DeliveryReducer.reduce(
            delivery,
            event: .attemptStarted(failedAttempt.attempt)
        )

        XCTAssertEqual(delivery.status, .queued)
        XCTAssertTrue(delivery.activeAttempts.isEmpty)
        XCTAssertEqual(delivery.failedAttempts, [failedAttempt])
    }

    func testAttemptStartThenFailureIsTerminalAndReplayIsIdempotent() {
        let failedAttempt = failure(number: 1, reason: .network)
        var delivery = DeliveryReducer.reduce(
            configuredDelivery(),
            event: .attemptStarted(failedAttempt.attempt)
        )
        delivery = DeliveryReducer.reduce(delivery, event: .attemptStarted(failedAttempt.attempt))
        delivery = DeliveryReducer.reduce(delivery, event: .attemptFailed(failedAttempt))
        delivery = DeliveryReducer.reduce(delivery, event: .attemptFailed(failedAttempt))

        XCTAssertEqual(delivery.status, .queued)
        XCTAssertTrue(delivery.activeAttempts.isEmpty)
        XCTAssertEqual(delivery.failedAttempts, [failedAttempt])
    }

    private func configuredDelivery() -> Delivery {
        DeliveryReducer.reduce(.pending, event: .configurationAvailabilityChanged(true))
    }

    private func attempt(number: Int, device: AttemptDevice = .iphone) -> Attempt {
        Attempt(
            id: attemptID(number),
            noteID: noteID,
            configurationRevisionID: revisionID,
            device: device,
            endpoint: SanitizedEndpoint(scheme: "https", host: "example.com", path: "/whim"),
            startedAt: now
        )
    }

    private func failure(
        number: Int,
        device: AttemptDevice = .iphone,
        reason: AttemptFailureReason
    ) -> AttemptFailure {
        AttemptFailure(
            attempt: attempt(number: number, device: device),
            failedAt: now,
            reason: reason
        )
    }

    private func receipt(number: Int) -> Receipt {
        Receipt(
            attemptID: attemptID(number),
            noteID: noteID,
            receivedAt: now,
            statusCode: 200
        )
    }

    private func attemptID(_ number: Int) -> AttemptID {
        AttemptID(
            rawValue: UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", number))!
        )
    }
}
