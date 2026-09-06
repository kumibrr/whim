import XCTest
import WhimCore
@testable import ExpoWhim

final class ExpoWhimModuleIntegrationTests: XCTestCase {
    func testNativeModuleUsesWhimCoreSchemaVersion() {
        XCTAssertEqual(ExpoWhimModule.schemaVersion, WhimCoreVersion.schema)
    }

    func testBridgeExposesAsyncProjectionAndStableRedactedErrors() async throws {
        let client = BridgeClientFake()
        let bridge = ExpoWhimBridge(client: client)

        let recordingJSON = try await bridge.startRecording(source: "iphone")
        let recording = try JSONSerialization.jsonObject(with: Data(recordingJSON.utf8)) as? [String: Any]
        XCTAssertEqual(recording?["schemaVersion"] as? Int, 1)
        XCTAssertEqual(recording?["noteID"] as? String, "22222222-2222-2222-2222-222222222222")

        do {
            try await bridge.updateWebhook(json: #"{"endpoint":"https://user:super-secret@example.com","bearerToken":"super-secret","hmacSecret":null,"customHeaders":[]}"#)
            XCTFail("Invalid configuration succeeded")
        } catch let error as ExpoWhimBridgeError {
            XCTAssertEqual(error.payload.code, "invalid_configuration")
            XCTAssertEqual(error.payload.field, "endpoint")
            XCTAssertFalse(error.description.contains("super-secret"))
        }
    }

    func testHostBundleDecodesTheSameNotesV1ContractFixture() throws {
        let resourceBundleURL = try XCTUnwrap([Bundle.main, Bundle(for: ExpoWhimModule.self)].compactMap {
            $0.url(forResource: "ExpoWhimContracts", withExtension: "bundle")
        }.first)
        let resourceBundle = try XCTUnwrap(Bundle(url: resourceBundleURL))
        let url = try XCTUnwrap(resourceBundle.url(forResource: "notes-v1.fixture", withExtension: "json"))
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let events = try decoder.decode([WhimEvent].self, from: Data(contentsOf: url))
        XCTAssertEqual(events.map(\.sequence), Array(1...13).map(UInt64.init))
        XCTAssertEqual(events.last?.type, .notesReset)
    }
}

private final class BridgeClientFake: WhimClient, @unchecked Sendable {
    private let stream = AsyncStream<WhimEvent> { $0.finish() }
    func startRecording(source: CaptureSource) async throws -> RecordingProjection {
        RecordingProjection(sessionID: "11111111-1111-1111-1111-111111111111",
            noteID: "22222222-2222-2222-2222-222222222222", source: source,
            createdAt: Date(timeIntervalSince1970: 1_788_553_200))
    }
    func activeRecording() async throws -> RecordingProjection? { nil }
    func stopRecording() async throws -> NoteProjection? { nil }
    func discardRecording() async throws {}
    func listNotes(filter: NoteFilter) async throws -> [NoteProjection] { [] }
    func note(id: NoteID) async throws -> NoteDetailProjection? { nil }
    func retry(noteID: NoteID) async throws {}
    func retryAllFailed() async throws -> Int { 0 }
    func sendRecovered(noteID: NoteID) async throws {}
    func delete(noteID: NoteID) async throws {}
    func updateWebhook(_ input: WebhookConfigurationInput) async throws -> ConfigurationUpdateResult {
        throw WhimServiceError.invalidConfiguration(field: "endpoint")
    }
    func testWebhook() async throws -> ConfigurationTestResult {
        .init(passed: true, statusCode: 204, idempotencyConfirmed: true)
    }
    func updatePreferences(_ input: PreferenceInput) async throws {}
    func reset() async throws {}
    func events() -> AsyncStream<WhimEvent> { stream }
}
