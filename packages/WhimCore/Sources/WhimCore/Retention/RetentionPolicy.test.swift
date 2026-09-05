import XCTest
@testable import WhimCore

final class RetentionPolicyTests: XCTestCase {
    func testStableRawValues() {
        XCTAssertEqual(RetentionPolicy.immediately.rawValue, 0)
        XCTAssertEqual(RetentionPolicy.oneDay.rawValue, 1)
        XCTAssertEqual(RetentionPolicy.sevenDays.rawValue, 7)
        XCTAssertEqual(RetentionPolicy.thirtyDays.rawValue, 30)
        XCTAssertEqual(RetentionPolicy.ninetyDays.rawValue, 90)
        XCTAssertEqual(RetentionPolicy.never.rawValue, -1)
    }
}
