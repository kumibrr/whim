#if os(iOS) && canImport(WatchConnectivity)
import Foundation
import WatchConnectivity
import XCTest
import WhimCore

final class WatchConnectivitySessionIntegrationTests: XCTestCase {
    // Exercise the SDK delegate callback without activating or requiring a paired Watch.
    func testActivationFailureReachesAdapterAndSuccessfulCallbackClearsIt() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let system = try SystemWatchConnectivitySession(receivedRoot: root.appendingPathComponent("Inbox"),
            databaseURL: root.appendingPathComponent("whim.sqlite"))
        let adapter = WatchConnectivityAdapter(session: system)
        system.session(.default, activationDidCompleteWith: .notActivated,
            error: NSError(domain: "WCErrorDomain", code: 7004,
                userInfo: [NSLocalizedDescriptionKey: "/private/secret.m4a"]))
        XCTAssertEqual(adapter.connectionDetails?.activationFailure?.category, "sessionNotActivated")
        XCTAssertEqual(adapter.connectionDetails?.activationFailure?.code, 7004)
        XCTAssertNotNil(adapter.connectionDetails?.activationFailure?.observedAt)
        system.session(.default, didFinish: WCSessionUserInfoTransfer(),
            error: NSError(domain: "WCErrorDomain", code: 7017))
        XCTAssertEqual(adapter.connectionDetails?.lastTransferFailure?.category, "transferTimedOut")
        system.session(.default, activationDidCompleteWith: .activated, error: nil)
        XCTAssertNil(adapter.connectionDetails?.activationFailure)
        XCTAssertEqual(adapter.connectionDetails?.lastTransferFailure?.code, 7017,
            "Activation recovery must not erase the labelled historical transfer failure")
    }
}
#endif
