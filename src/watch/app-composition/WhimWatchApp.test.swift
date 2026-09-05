import XCTest
@testable import WhimWatch

final class WhimWatchAppTests: XCTestCase {
    func testRootUsesStableAccessibilityIdentifier() {
        XCTAssertEqual(WhimWatchRoot.accessibilityIdentifier, "watch-root")
    }
}
