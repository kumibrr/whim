import XCTest
@testable import WhimIPhone

final class TimelineFormatTests: XCTestCase {
    func testDurationMatchesCurrentUI() {
        XCTAssertEqual(TimelineFormat.duration(seconds: -1), "0:00")
        XCTAssertEqual(TimelineFormat.duration(seconds: 65.9), "1:05")
        XCTAssertEqual(TimelineFormat.duration(seconds: 300), "5:00")
    }
}
