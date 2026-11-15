import XCTest
@testable import WhimCore

final class ComplicationWidgetKindTests: XCTestCase {
    // Break: recording changes refresh only the original picker entry.
    func testReloadsEveryCornerConfigurationExactlyOnce() {
        var reloaded = [String]()
        ComplicationWidgetKind.reloadAll { reloaded.append($0) }
        let expected = ["app.whim.recording", "app.whim.recording.corner.topLeft",
                        "app.whim.recording.corner.bottomRight", "app.whim.recording.corner.bottomLeft"]
        XCTAssertEqual(Set(reloaded), Set(expected))
        for kind in expected { XCTAssertEqual(reloaded.filter { $0 == kind }.count, 1) }
    }
}
