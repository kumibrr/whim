import Foundation
import XCTest
@testable import WhimCore

final class IPhoneAudioSessionAdapterTests: XCTestCase {
    func testForegroundCaptureUsesExclusiveRecordSession() throws {
        let hardware = IPhoneSessionHardware()
        try hardware.adapter.activate()
        hardware.adapter.deactivate()
        XCTAssertEqual(hardware.values, ["exclusive", "active", "inactive"])
    }

    // Break: Lock Screen capture starts in the background, where an exclusive session cannot interrupt others.
    func testBackgroundCaptureFallsBackToMixableSessionWhenInterruptionIsDenied() throws {
        let hardware = IPhoneSessionHardware(failures: [IPhoneAudioSessionAdapter.cannotInterruptOthers])
        try hardware.adapter.activate()
        XCTAssertEqual(hardware.values, ["exclusive", "denied", "mixable", "active"])
    }

    func testUnrelatedActivationFailureIsNotRetried() {
        let hardware = IPhoneSessionHardware(failures: [NSError(domain: NSOSStatusErrorDomain, code: 561017449)])
        XCTAssertThrowsError(try hardware.adapter.activate())
        XCTAssertEqual(hardware.values, ["exclusive", "denied"])
    }
}

private final class IPhoneSessionHardware: @unchecked Sendable {
    var values: [String] = []
    var failures: [Error]
    init(failures: [Error] = []) { self.failures = failures }
    var adapter: IPhoneAudioSessionAdapter {
        IPhoneAudioSessionAdapter(configure: { mixable in
            self.values.append(mixable ? "mixable" : "exclusive")
        }, setActive: { active in
            if active, !self.failures.isEmpty {
                self.values.append("denied")
                throw self.failures.removeFirst()
            }
            self.values.append(active ? "active" : "inactive")
        })
    }
}
