import XCTest
import WhimCore

final class WhimCoreIntegrationSmokeTests: XCTestCase {
    func testConsumerCanReadSchemaVersion() {
        XCTAssertEqual(WhimCoreVersion.schema, 1)
    }
}
