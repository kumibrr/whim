import XCTest

final class WhimWatchUITests: XCTestCase {
    @MainActor
    func testLaunchShowsWhimRoot() {
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(app.descendants(matching: .any)["watch-root"].waitForExistence(timeout: 10))
    }
}
