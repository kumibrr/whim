import XCTest
import WhimCore
@testable import ExpoWhim

final class ExpoWhimModuleIntegrationTests: XCTestCase {
    func testNativeModuleUsesWhimCoreSchemaVersion() {
        XCTAssertEqual(ExpoWhimModule.schemaVersion, WhimCoreVersion.schema)
    }
}
