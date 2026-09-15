import ExpoModulesCore
import Foundation
import WhimCorePod

public struct ExpoWhimErrorPayload: Codable, Equatable, Sendable {
    public let code: String
    public let message: String
    public let field: String?
}

public struct ExpoWhimBridgeError: Error, CustomStringConvertible, LocalizedError, Sendable {
    public let payload: ExpoWhimErrorPayload
    public var description: String { (try? ExpoWhimJSON.encode(payload)) ?? #"{"code":"operation_failed","message":"Whim could not complete the request."}"# }
    public var errorDescription: String? { description }
}

public struct ExpoWhimBridge: Sendable {
    private let client: any WhimClient
    public init(client: any WhimClient) { self.client = client }

    public func getSettings() async throws -> String {
        try await perform { try ExpoWhimJSON.encode(await client.settings()) }
    }
    public func patchWebhook(json: String) async throws -> String {
        try await perform { try ExpoWhimJSON.encode(await client.patchWebhook(ExpoWhimJSON.decode(WebhookPatch.self, json))) }
    }
    public func completeOnboarding() async throws { try await perform { try await client.completeOnboarding() } }
    public func requestPermission(kind: String) async throws -> String {
        try await perform {
            guard let kind = PermissionKind(rawValue: kind) else { throw WhimServiceError.invalidIdentifier(field: "permission") }
            return try ExpoWhimJSON.encode(await client.requestPermission(kind))
        }
    }
    public func openSystemSettings() async throws { try await perform { try await client.openSystemSettings() } }
    public func playNote(id: String) async throws -> String {
        try await perform { try ExpoWhimJSON.encode(await client.playNote(noteID(id))) }
    }
    public func stopPlayback() async { await client.stopPlayback() }
    public func getPlayback() async throws -> String { try ExpoWhimJSON.encode(await client.playbackSnapshot()) }

    public func startRecording(source: String) async throws -> String {
        try await perform {
            guard let source = CaptureSource(rawValue: source) else {
                throw WhimServiceError.invalidIdentifier(field: "source")
            }
            return try ExpoWhimJSON.encode(await client.startRecording(source: source))
        }
    }
    public func getActiveRecording() async throws -> String {
        try await perform { try ExpoWhimJSON.encode(await client.activeRecording()) }
    }
    public func stopRecording() async throws -> String {
        try await perform { try ExpoWhimJSON.encode(await client.stopRecording()) }
    }
    public func discardRecording() async throws { try await perform { try await client.discardRecording() } }
    public func listNotes(filter: String) async throws -> String {
        try await perform {
            guard let filter = NoteFilter(rawValue: filter) else {
                throw WhimServiceError.invalidIdentifier(field: "filter")
            }
            return try ExpoWhimJSON.encode(await client.listNotes(filter: filter))
        }
    }
    public func getNote(id: String) async throws -> String {
        try await perform { try ExpoWhimJSON.encode(await client.note(id: try noteID(id))) }
    }
    public func retry(noteID: String) async throws {
        try await perform { try await client.retry(noteID: try self.noteID(noteID)) }
    }
    public func retryAllFailed() async throws -> Int { try await perform { try await client.retryAllFailed() } }
    public func sendRecovered(noteID: String) async throws {
        try await perform { try await client.sendRecovered(noteID: try self.noteID(noteID)) }
    }
    public func deleteNote(noteID: String) async throws {
        try await perform { try await client.delete(noteID: try self.noteID(noteID)) }
    }
    public func updateWebhook(json: String) async throws -> String {
        try await perform {
            let input = try ExpoWhimJSON.decode(ExpoWebhookInput.self, json)
            let value = try await client.updateWebhook(.init(endpoint: input.endpoint,
                bearerToken: input.bearerToken, hmacSecret: input.hmacSecret,
                customHeaders: input.customHeaders))
            return try ExpoWhimJSON.encode(value)
        }
    }
    public func testWebhook() async throws -> String {
        try await perform { try ExpoWhimJSON.encode(await client.testWebhook()) }
    }
    public func updatePreferences(json: String) async throws {
        try await perform { try await client.updatePreferences(ExpoWhimJSON.decode(PreferenceInput.self, json)) }
    }
    public func reset() async throws { try await perform { try await client.reset() } }

    private func noteID(_ raw: String) throws -> NoteID {
        guard let value = UUID(uuidString: raw) else { throw WhimServiceError.invalidIdentifier(field: "noteID") }
        return NoteID(rawValue: value)
    }
    private func perform<T>(_ operation: () async throws -> T) async throws -> T {
        do { return try await operation() }
        catch let error as ExpoWhimBridgeError { throw error }
        catch { throw ExpoWhimBridgeError(payload: Self.payload(error)) }
    }
    private static func payload(_ error: any Error) -> ExpoWhimErrorPayload {
        switch error {
        case WhimServiceError.recordingActive:
            .init(code: "recording_active", message: "Stop recording before playing a Note.", field: nil)
        case WhimServiceError.audioUnavailable:
            .init(code: "audio_unavailable", message: "This Note's audio is unavailable.", field: nil)
        case WhimServiceError.permissionDenied:
            .init(code: "microphone_permission_required", message: "Microphone access is required. Open Settings to allow access.", field: nil)
        case WhimServiceError.invalidConfiguration(let field):
            .init(code: "invalid_configuration", message: "Enter a valid webhook configuration.", field: field)
        case WhimServiceError.invalidIdentifier(let field):
            .init(code: "invalid_identifier", message: "The identifier is invalid.", field: field)
        case WhimServiceError.setupRequired:
            .init(code: "setup_required", message: "Whim setup is required.", field: nil)
        case ConfigurationTestError.missingConfiguration:
            .init(code: "setup_required", message: "Configure a webhook before testing it.", field: "endpoint")
        case WhimStoreError.missingNote:
            .init(code: "note_not_found", message: "The Note no longer exists.", field: "noteID")
        case WhimStoreError.notEligible:
            .init(code: "note_not_eligible", message: "The Note is not eligible for this command.", field: "noteID")
        default:
            .init(code: "operation_failed", message: "Whim could not complete the request.", field: nil)
        }
    }
}

private struct ExpoWebhookInput: Codable {
    let endpoint: String
    let bearerToken: String?
    let hmacSecret: String?
    let customHeaders: [CustomHeaderInput]
}

enum ExpoWhimJSON {
    static func encode<T: Encodable>(_ value: T) throws -> String {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            try container.encode(formatter.string(from: date))
        }
        return String(decoding: try encoder.encode(value), as: UTF8.self)
    }
    static func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try JSONDecoder().decode(type, from: Data(json.utf8))
    }
    static func object<T: Encodable>(_ value: T) throws -> [String: Any?] {
        try JSONSerialization.jsonObject(with: Data(encode(value).utf8)) as? [String: Any?] ?? [:]
    }
}

private actor ExpoWhimServiceProvider {
    private var task: Task<WhimService, Error>?
    func client() async throws -> any WhimClient {
        if let task { return try await task.value }
        let task = Task { try await WhimProductionComposition.make() }
        self.task = task
        return try await task.value
    }
}

final class ExpoWhimEventForwarder: @unchecked Sendable {
    typealias ClientProvider = @Sendable () async throws -> any WhimClient
    typealias Sink = @Sendable (WhimEvent) async -> Void
    private let lock = NSLock()
    private let client: ClientProvider
    private var task: Task<Void, Never>?

    init(client: @escaping ClientProvider) { self.client = client }

    func start(sink: @escaping Sink) {
        lock.withLock {
            guard task == nil else { return }
            let client = client
            task = Task {
                do {
                    for await event in try await client().events() {
                        guard !Task.isCancelled else { return }
                        await sink(event)
                    }
                } catch { }
            }
        }
    }

    func stop() {
        let task = lock.withLock { () -> Task<Void, Never>? in
            defer { self.task = nil }
            return self.task
        }
        task?.cancel()
    }
}

public final class ExpoWhimModule: Module {
    public static let schemaVersion = WhimCoreVersion.schema
    private let provider = ExpoWhimServiceProvider()
    private lazy var eventForwarder = ExpoWhimEventForwarder(client: { [provider] in
        try await provider.client()
    })

    public func definition() -> ModuleDefinition {
        Name("ExpoWhim")
        Events("onWhimEvent")
        Function("schemaVersion") { Self.schemaVersion }
        AsyncFunction("getSettings") { () async throws -> String in try await self.bridge().getSettings() }
        AsyncFunction("patchWebhook") { (json: String) async throws -> String in try await self.bridge().patchWebhook(json: json) }
        AsyncFunction("completeOnboarding") { () async throws in try await self.bridge().completeOnboarding() }
        AsyncFunction("requestPermission") { (kind: String) async throws -> String in try await self.bridge().requestPermission(kind: kind) }
        AsyncFunction("openSystemSettings") { () async throws in try await self.bridge().openSystemSettings() }
        AsyncFunction("playNote") { (id: String) async throws -> String in try await self.bridge().playNote(id: id) }
        AsyncFunction("stopPlayback") { () async throws in try await self.bridge().stopPlayback() }
        AsyncFunction("getPlayback") { () async throws -> String in try await self.bridge().getPlayback() }
        AsyncFunction("startRecording") { (source: String) async throws -> String in
            try await self.bridge().startRecording(source: source)
        }
        AsyncFunction("getActiveRecording") { () async throws -> String in
            try await self.bridge().getActiveRecording()
        }
        AsyncFunction("stopRecording") { () async throws -> String in try await self.bridge().stopRecording() }
        AsyncFunction("discardRecording") { () async throws in try await self.bridge().discardRecording() }
        AsyncFunction("listNotes") { (filter: String) async throws -> String in try await self.bridge().listNotes(filter: filter) }
        AsyncFunction("getNote") { (id: String) async throws -> String in try await self.bridge().getNote(id: id) }
        AsyncFunction("retry") { (id: String) async throws in try await self.bridge().retry(noteID: id) }
        AsyncFunction("retryAllFailed") { () async throws -> Int in try await self.bridge().retryAllFailed() }
        AsyncFunction("sendRecovered") { (id: String) async throws in try await self.bridge().sendRecovered(noteID: id) }
        AsyncFunction("deleteNote") { (id: String) async throws in try await self.bridge().deleteNote(noteID: id) }
        AsyncFunction("updateWebhook") { (json: String) async throws -> String in try await self.bridge().updateWebhook(json: json) }
        AsyncFunction("testWebhook") { () async throws -> String in try await self.bridge().testWebhook() }
        AsyncFunction("updatePreferences") { (json: String) async throws in try await self.bridge().updatePreferences(json: json) }
        AsyncFunction("reset") { () async throws in try await self.bridge().reset() }
        OnStartObserving("onWhimEvent") { self.startEventForwarding() }
        OnStopObserving("onWhimEvent") { self.stopEventForwarding() }
    }

    private func bridge() async throws -> ExpoWhimBridge { ExpoWhimBridge(client: try await provider.client()) }
    private func startEventForwarding() {
        eventForwarder.start { [weak self] event in
            guard let self, let body = try? ExpoWhimJSON.object(event) else { return }
            self.sendEvent("onWhimEvent", body)
        }
    }
    private func stopEventForwarding() { eventForwarder.stop() }
}

extension ExpoWhimModule: @unchecked Sendable {}
