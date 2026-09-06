import Foundation
import AVFoundation
import XCTest
@testable import WhimCore

final class WebhookIntegrationTests: XCTestCase {
    // Break: the bundled configuration test asset is absent, sensitive speech, or not playable AAC/M4A.
    func testBundledConfigurationAudioFixtureIsPlayableDeterministicTone() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "configuration-test-fixture", withExtension: "m4a",
            subdirectory: "Fixtures"))
        let audio = try AVAudioFile(forReading: url)
        XCTAssertGreaterThan(audio.length, 0)
        XCTAssertLessThan(Double(audio.length) / audio.fileFormat.sampleRate, 1)
    }
#if os(macOS)
    // Break: URLSession follows redirects, skips receiver verification, or retains an oversized response.
    func testLoopbackReceiverVerifiesContractRejectsRedirectsAndCapsBodies() async throws {
        let server = try LoopbackServer()
        defer { server.stop() }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let audioURL = root.appendingPathComponent("fixture.m4a")
        try Data("receiver-audio".utf8).write(to: audioURL)
        let note = Note(id: NoteID(), recordingSessionID: RecordingSessionID(), title: "Receiver test",
            titleSource: .timestamp, createdAt: Date(), duration: 1, source: .iphone,
            captureOutcome: .completed, requiresReview: false, audioURL: audioURL)
        let attemptID = AttemptID()
        let credentials = StoredWebhookCredentials(endpoint: server.url(path: "/receive"), bearerToken: nil,
            hmacSecret: "receiver-secret", customHeaders: [])
        let builder = WebhookRequestBuilder(temporaryDirectory: root)
        let request = try builder.build(note: note, attemptID: attemptID, credentials: credentials,
            timestamp: 1_000, appVersion: "1", appBuild: "1", boundary: "integration-boundary")
        defer { request.removeBodyFile() }
        let response = try await URLSessionHTTPTransport().send(request)
        XCTAssertEqual(response.statusCode, 200)
        XCTAssertEqual(response.header("X-Whim-Note-ID"), note.id.rawValue.uuidString.lowercased())

        let redirectCredentials = StoredWebhookCredentials(endpoint: server.url(path: "/redirect"), bearerToken: nil,
            hmacSecret: "receiver-secret", customHeaders: [])
        let redirect = try builder.build(note: note, attemptID: AttemptID(), credentials: redirectCredentials,
            timestamp: 1_001, appVersion: "1", appBuild: "1")
        defer { redirect.removeBodyFile() }
        let redirectResponse = try await URLSessionHTTPTransport().send(redirect)
        XCTAssertEqual(redirectResponse.statusCode, 302)

        let oversizedCredentials = StoredWebhookCredentials(endpoint: server.url(path: "/oversized"), bearerToken: nil,
            hmacSecret: "receiver-secret", customHeaders: [])
        let oversized = try builder.build(note: note, attemptID: AttemptID(), credentials: oversizedCredentials,
            timestamp: 1_002, appVersion: "1", appBuild: "1")
        defer { oversized.removeBodyFile() }
        let capped = try await URLSessionHTTPTransport().send(oversized)
        XCTAssertEqual(capped.body.count, DeliveryTimeouts.maximumErrorExcerptBytes)
    }
#endif
    // Break: multipart order/media types, digests, signing, or idempotency headers drift from v1.
    func testBuilderProducesExactSignedMultipartContract() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let audioURL = root.appendingPathComponent("audio.m4a")
        try Data("AUDIO-BYTES".utf8).write(to: audioURL)
        let noteID = NoteID(rawValue: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!)
        let attemptID = AttemptID(rawValue: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!)
        let note = Note(id: noteID, recordingSessionID: RecordingSessionID(), title: "A title", titleSource: .timestamp,
            createdAt: Date(timeIntervalSince1970: 1_788_553_200), duration: 1.25, source: .iphone,
            captureOutcome: .completed, requiresReview: false, audioURL: audioURL)
        let credentials = StoredWebhookCredentials(endpoint: URL(string: "https://example.com/hook?q=actual")!,
            bearerToken: "bearer", hmacSecret: "hmac", customHeaders: [.init(name: "X-Custom", value: "custom")])

        let request = try WebhookRequestBuilder(temporaryDirectory: root).build(note: note, attemptID: attemptID,
            credentials: credentials, timestamp: 1_788_553_200, event: "note.created", appVersion: "1.0.0", appBuild: "1",
            boundary: "whim-boundary")
        defer { request.removeBodyFile() }

        XCTAssertEqual(request.url.absoluteString, "https://example.com/hook?q=actual")
        XCTAssertEqual(request.method, "POST")
        XCTAssertEqual(request.headers["X-Whim-Note-ID"], noteID.rawValue.uuidString.lowercased())
        XCTAssertEqual(request.headers["X-Whim-Attempt-ID"], attemptID.rawValue.uuidString.lowercased())
        XCTAssertEqual(request.headers["Authorization"], "Bearer bearer")
        XCTAssertEqual(request.headers["X-Custom"], "custom")
        XCTAssertEqual(request.headers["X-Whim-Audio-SHA256"], "9c2e06637b8d660c2068fd84e98ae96f70d9df6286684f100ded8613e5a73d0a")
        XCTAssertTrue(request.headers["X-Whim-Signature"]!.hasPrefix("v1="))
        let body = try Data(contentsOf: request.bodyFileURL)
        let text = String(decoding: body, as: UTF8.self)
        let metadataRange = try XCTUnwrap(text.range(of: "name=\"metadata\""))
        let audioRange = try XCTUnwrap(text.range(of: "name=\"audio\""))
        XCTAssertLessThan(metadataRange.lowerBound, audioRange.lowerBound)
        XCTAssertTrue(text.contains("Content-Type: application/json\r\n\r\n{"))
        XCTAssertTrue(text.contains("Content-Type: audio/mp4\r\n\r\nAUDIO-BYTES\r\n--whim-boundary--\r\n"))
        XCTAssertEqual(Int64(body.count), request.contentLength)
    }
}

#if os(macOS)
private final class LoopbackServer {
    private let process = Process()
    private let port: Int

    init() throws {
        let script = try XCTUnwrap(Bundle.module.url(forResource: "webhook-server", withExtension: "mjs",
            subdirectory: "Fixtures"))
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["node", script.path]
        process.environment = ProcessInfo.processInfo.environment.merging([
            "WHIM_WEBHOOK_PORT": "0", "WHIM_HMAC_SECRET": "receiver-secret",
        ]) { _, new in new }
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let data = pipe.fileHandleForReading.availableData
        guard let line = String(data: data, encoding: .utf8)?.split(separator: "\n").first,
              let json = try JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
              let port = json["port"] as? Int else {
            process.terminate()
            throw HTTPTransportError.invalidResponse
        }
        self.port = port
    }

    func url(path: String) -> URL { URL(string: "http://127.0.0.1:\(port)\(path)")! }
    func stop() { if process.isRunning { process.terminate(); process.waitUntilExit() } }
}
#endif
