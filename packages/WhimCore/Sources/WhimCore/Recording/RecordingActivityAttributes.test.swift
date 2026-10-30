import Foundation
import XCTest
@testable import WhimCore

final class RecordingActivityAttributesTests: XCTestCase {
    // Break: published activity state drops voice measurements or resets the elapsed timer.
    func testVoiceMeasurementsRoundTripWithoutChangingTheStartTime() throws {
        let startedAt = Date(timeIntervalSince1970: 123)
        let content = RecordingActivityContent(startedAt: startedAt, power: -12, tone: 0.75)
        let decoded = try JSONDecoder().decode(RecordingActivityContent.self,
            from: JSONEncoder().encode(content))
        XCTAssertEqual(decoded.startedAt, startedAt)
        XCTAssertEqual(decoded.power, -12)
        XCTAssertEqual(decoded.tone, 0.75)
    }

    // Break: an activity initially invents voice energy, or an old activity cannot decode after an app update.
    func testInitialAndOlderActivityContentRenderSilence() throws {
        let old = Data(#"{"startedAt":123}"#.utf8)
        let content = try JSONDecoder().decode(RecordingActivityContent.self, from: old)
        XCTAssertEqual(content.startedAt, Date(timeIntervalSinceReferenceDate: 123))
        XCTAssertEqual(content.power, -160)
        XCTAssertEqual(content.tone, 0)
        let initial = RecordingActivityContent(startedAt: content.startedAt)
        XCTAssertEqual(initial, content)
    }

    // Break: nonfinite meter values make an ActivityKit content update unencodable.
    func testInvalidMeasurementsRemainEncodableAndBounded() throws {
        let content = RecordingActivityContent(startedAt: Date(), power: .nan, tone: .infinity)
        XCTAssertNoThrow(try JSONEncoder().encode(content))
        XCTAssertEqual(content.power, -160)
        XCTAssertEqual(content.tone, 0)
        let loud = RecordingActivityContent(startedAt: Date(), power: 12, tone: 2)
        XCTAssertEqual(loud.power, 0)
        XCTAssertEqual(loud.tone, 1)
    }
}
