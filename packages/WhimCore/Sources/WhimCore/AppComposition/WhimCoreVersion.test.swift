import XCTest
@testable import WhimCore

final class WhimCoreSmokeTests: XCTestCase {
    func testExposesSchemaVersion() {
        XCTAssertEqual(WhimCoreVersion.schema, 1)
    }
}
