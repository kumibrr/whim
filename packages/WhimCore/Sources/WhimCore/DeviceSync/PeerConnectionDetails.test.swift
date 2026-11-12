import Foundation
import XCTest
import WhimCore

final class PeerConnectionDetailsTests: XCTestCase {
    // Break: exposing raw NSError messages/userInfo or losing its safe identity.
    func testSystemErrorsRetainOnlySafeIdentityAndObservationTime() throws {
        let time = Date(timeIntervalSince1970: 1_790_000_000)
        let failure = SynchronizationSystemError(error: NSError(domain: "WCErrorDomain", code: 7017,
            userInfo: [NSLocalizedDescriptionKey: "private audio /secret/note.m4a https://host/?token=secret",
                "Authorization": "Bearer private-token"]), observedAt: time)
        XCTAssertEqual(failure.domain, "WCErrorDomain")
        XCTAssertEqual(failure.code, 7017)
        XCTAssertEqual(failure.category, "transferTimedOut")
        XCTAssertEqual(failure.observedAt, time)
        let encoded = try JSONEncoder().encode(failure)
        XCTAssertFalse(String(decoding: encoded, as: UTF8.self).contains("secret"))
        XCTAssertFalse(String(decoding: encoded, as: UTF8.self).contains("private"))
        XCTAssertEqual(try JSONDecoder().decode(SynchronizationSystemError.self, from: encoded), failure)
    }

    func testUnrecognizedDomainsCannotPersistArbitraryStringsOrCodes() throws {
        let failure = SynchronizationSystemError(error: NSError(domain: "https://private.invalid/token", code: 42),
            observedAt: Date(timeIntervalSince1970: 1_790_000_000))
        XCTAssertNil(failure.domain)
        XCTAssertNil(failure.code)
        XCTAssertEqual(failure.category, "unknown")
        let incoming = Data(#"{"domain":"/private/note.m4a","code":42}"#.utf8)
        let decoded = try JSONDecoder().decode(SynchronizationSystemError.self, from: incoming)
        XCTAssertNil(decoded.domain)
        XCTAssertNil(decoded.code)
        XCTAssertNil(decoded.observedAt, "An absent observation time must not be invented")
    }

    func testStorageExhaustionHasAStableCategory() {
        let failure = SynchronizationSystemError(error: POSIXError(.ENOSPC), observedAt: Date())
        XCTAssertEqual(failure.category, "storageFull")
    }

    func testLegacyAndFutureConnectionFactsRemainLoadable() throws {
        let unknown = try JSONDecoder().decode(PeerConnectionDetails.self, from: Data("{}".utf8))
        XCTAssertNil(unknown.supported)
        XCTAssertNil(unknown.activationState)
        XCTAssertNil(unknown.activationFailure)
        let future = try JSONDecoder().decode(PeerConnectionDetails.self,
            from: Data(#"{"activationState":"futureState","futureFact":true}"#.utf8))
        XCTAssertNil(future.activationState)
    }
}
