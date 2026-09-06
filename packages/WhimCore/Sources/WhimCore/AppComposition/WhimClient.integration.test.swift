import Foundation
import XCTest
@testable import WhimCore

final class WhimEventContractIntegrationTests: XCTestCase {
    func testDecodesSharedNotesV1FixtureWithStableDatesOptionalsAndEnums() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "notes-v1.fixture", withExtension: "json"))
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let events = try decoder.decode([WhimEvent].self, from: Data(contentsOf: url))

        XCTAssertEqual(events.map(\.type), [.recordingStarted, .recordingProgress,
            .recordingRouteChanged, .recordingMaximumDurationWarning, .recordingStopped,
            .recordingDiscarded, .noteChanged, .noteChanged, .noteChanged, .noteChanged,
            .noteChanged, .noteDeleted, .notesReset])
        XCTAssertEqual(events.map(\.sequence), Array(1...13).map(UInt64.init))
        XCTAssertTrue(events.allSatisfy { $0.schemaVersion == 1 })
        XCTAssertEqual(events[0].recording?.source, .iphone)
        XCTAssertEqual(events[0].recording?.createdAt, Date(timeIntervalSince1970: 1_788_553_200))
        XCTAssertEqual(events[1].elapsedSeconds, 42.25)
        XCTAssertEqual(events[6].note?.source, .appleWatch)
        XCTAssertEqual(events[6].note?.status, .failed)
        XCTAssertEqual(events[6].note?.localError, .unreadable)
        XCTAssertEqual(events[6...10].compactMap(\.note?.status),
            [.failed, .setupRequired, .queued, .sending, .sent])
        XCTAssertEqual(events[6...10].map(\.note?.localError),
            [.unreadable, .storageFull, .missing, .durabilityFailure, nil])
        XCTAssertEqual(events[6...10].map(\.note?.workflowError),
            [.deliveryPreparationFailed, .deliveryPersistenceFailed, nil, nil, nil])
        XCTAssertNil(events[12].note)
    }

    func testPreferenceContractUsesEveryExternalRetentionRawValue() throws {
        let encoder = JSONEncoder()
        let values = try RetentionPolicy.allCases.map { policy -> String in
            let input = PreferenceInput(retentionPolicy: policy, transcriptionEnabled: true,
                transcriptionLocaleIdentifier: nil)
            let object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoder.encode(input)) as? [String: Any])
            return try XCTUnwrap(object["retentionPolicy"] as? String)
        }
        XCTAssertEqual(values, ["immediately", "one_day", "seven_days", "thirty_days", "ninety_days", "never"])
    }
}
