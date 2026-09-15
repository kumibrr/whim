import XCTest
@testable import WhimCore

final class WatchAudioSessionAdapterTests: XCTestCase {
    func testCaptureConfiguresBeforeActivationAndReleasesSession() throws {
        let hardware = WatchSessionHardware()
        let adapter = WatchAudioSessionAdapter(configure: {
            hardware.values.append("record/default")
        }, setActive: { active in hardware.values.append(active ? "active" : "inactive") })
        try adapter.activate()
        adapter.deactivate()
        XCTAssertEqual(hardware.values, ["record/default", "active", "inactive"])
    }
}
private final class WatchSessionHardware: @unchecked Sendable { var values: [String] = [] }
