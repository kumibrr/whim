import Foundation
import XCTest
import WhimCore
import WhimIPhone

final class WatchConnectionDetailsTests: XCTestCase {
    private func details(_ reason: String?, facts: PeerConnectionDetails? = nil, available: Bool = false) -> WatchConnectionDetails {
        .init(settings: .init(availability: available ? "available" : "unavailable", lastSynchronizedAt: nil,
            resetState: "unavailable", availabilityReason: reason, connectionDetails: facts))
    }
    func testKnownCausesOfferRecoveryWithoutDestructiveAdvice() {
        for (reason, cause, action) in [
            ("unsupported", "not supported", "iPhone"),
            ("inactive", "not started", "both devices"),
            ("unpaired", "No Apple Watch", "pair"),
            ("appNotInstalled", "not installed", "Watch app")
        ] {
            let value = details(reason)
            XCTAssertTrue(value.cause?.contains(cause) == true, reason)
            XCTAssertTrue(value.recovery?.contains(action) == true, reason)
            XCTAssertFalse(value.recovery?.contains("remove") == true)
        }
    }
    func testObservedActivationCausesOfferTheMatchingRecoveryAction() {
        for (code, action) in [(7005, "pair"), (7006, "installation"), (7015, "storage")] {
            let failure = SynchronizationSystemError(error: NSError(domain: "WCErrorDomain", code: code), observedAt: Date())
            let value = details("inactive", facts: .init(activationFailure: failure))
            XCTAssertTrue(value.recovery?.contains(action) == true, "WCErrorDomain \(code)")
        }
    }
    func testUnknownIsExplicitAndMissingFactsAreNotInvented() {
        for reason in [nil, "futureReason"] {
            let value = details(reason)
            XCTAssertTrue(value.cause?.contains("cannot determine") == true)
            XCTAssertTrue(value.technicalRows.contains(.init("Activation", "Not reported")))
            XCTAssertFalse(value.technicalRows.contains { $0.label.contains("error code") })
        }
    }
    func testActualActivationErrorIsShownButHistoricalTransferFailureCannotBecomeCurrentCause() {
        let error = SynchronizationSystemError(error: NSError(domain: "WCErrorDomain", code: 7004,
            userInfo: [NSLocalizedDescriptionKey: "secret"]), observedAt: Date(timeIntervalSince1970: 1000))
        let failed = details("inactive", facts: .init(activationFailure: error))
        XCTAssertTrue(failed.cause?.contains("could not start") == true)
        XCTAssertTrue(failed.technicalRows.contains(.init("Activation error code", "7004")))
        let active = details(nil, facts: .init(reachable: false, lastTransferFailure: error), available: true)
        XCTAssertNil(active.cause)
        XCTAssertNil(active.recovery)
        XCTAssertTrue(active.technicalRows.contains(.init("Immediately reachable", "No")))
        XCTAssertTrue(active.technicalRows.contains(.init("Last transfer error code", "7004")))
        XCTAssertFalse(active.technicalRows.contains { $0.value.contains("secret") })
    }
}
