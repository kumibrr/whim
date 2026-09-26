#if DEBUG
import Foundation

/// Installed simulator journeys replace only the authenticated peer boundary.
/// Every injected message enters the same versioned protocol and WhimService as WCSession.
public final class DebugPeerTransport: PeerTransport, @unchecked Sendable {
    private let scenario: String
    private let fixture: URL
    private let lock = NSLock()
    private var receiver: (@Sendable (PeerEvent) -> Void)?
    private var raced: Set<NoteID> = []
    public var isAvailable: Bool { scenario != "isolated" }
    public var isActivated: Bool { true }
    public var isReachable: Bool { isAvailable }
    private init(scenario: String, fixture: URL) { self.scenario = scenario; self.fixture = fixture }
    public static func from(arguments: [String], fixture: URL) throws -> DebugPeerTransport? {
        guard let index = arguments.firstIndex(of: "-WhimPeerScenario") else {
            let fixtureFlags = ["-WhimFixtureAudio", "-WhimFixtureWebhookURL", "-WhimWatchTestID"]
            return arguments.contains(where: fixtureFlags.contains) ? .init(scenario: "isolated", fixture: fixture) : nil
        }
        guard arguments.indices.contains(index + 1),
              ["file-first", "state-first", "receipt-first", "failure-first"].contains(arguments[index + 1]) else {
            throw WhimServiceError.setupRequired("Unknown development peer scenario.")
        }
        let audio: URL
        if let audioIndex = arguments.firstIndex(of: "-WhimFixtureAudio"), arguments.indices.contains(audioIndex + 1) {
            audio = URL(fileURLWithPath: arguments[audioIndex + 1])
        } else { audio = fixture }
        return .init(scenario: arguments[index + 1], fixture: audio)
    }
    public func activate(receive: @escaping @Sendable (PeerEvent) -> Void) {
        lock.withLock { receiver = receive }
        receive(.activated)
        guard scenario == "file-first" || scenario == "state-first" else { return }
        // This journey exercises delivery ordering and playback, not expired retention.
        let receivedAt = Date()
        let id = NoteID(rawValue: UUID(uuidString: "09000000-0000-0000-0000-000000000001")!)
        let metadata = ConnectivityEnvelope(payload: .noteMetadata(.init(id: id,
            recordingSessionID: .init(rawValue: UUID(uuidString: "09000000-0000-0000-0000-000000000002")!),
            title: "Peer recording", titleSource: .timestamp, createdAt: receivedAt.addingTimeInterval(-2),
            duration: 1, source: .appleWatch, captureOutcome: .completed, requiresReview: false)))
        let attempt = Attempt(noteID: id, configurationRevisionID: ConfigurationRevisionID(), device: .appleWatch,
            endpoint: .init(scheme: "https", host: "whim-fixture.invalid", path: "/receive"), startedAt: receivedAt.addingTimeInterval(-2))
        let failure = ConnectivityEnvelope(payload: .attempt(.failed(.init(attempt: attempt,
            failedAt: receivedAt.addingTimeInterval(-1), reason: .network))))
        let receipt = ConnectivityEnvelope(payload: .receipt(.init(attemptID: AttemptID(), noteID: id,
            receivedAt: receivedAt, statusCode: 204)))
        let title = ConnectivityEnvelope(payload: .title(.init(noteID: id, title: "From paired Watch", source: .transcription)))
        let states: [PeerEvent] = [.message(receipt), .message(failure), .message(metadata), .message(title), .message(receipt)]
        if scenario == "file-first" { receive(.file(fixture, metadata)) }
        states.forEach(receive)
        if scenario == "state-first" { receive(.file(fixture, metadata)) }
    }
    public func transfer(_ envelope: ConnectivityEnvelope) throws {
        guard scenario == "receipt-first" || scenario == "failure-first",
              case .attempt(let transfer) = envelope.payload else { return }
        let watch: Attempt
        switch transfer { case .started(let value): watch = value; case .failed(let value): watch = value.attempt }
        guard watch.device == .appleWatch else { return }
        let receiver = lock.withLock { () -> (@Sendable (PeerEvent) -> Void)? in
            guard raced.insert(watch.noteID).inserted else { return nil }
            return self.receiver
        }
        guard let receiver else { return }
        let phone = Attempt(noteID: watch.noteID, configurationRevisionID: watch.configurationRevisionID, device: .iphone,
            endpoint: watch.endpoint, startedAt: watch.startedAt)
        let failure = ConnectivityEnvelope(generation: envelope.generation, payload: .attempt(.failed(.init(attempt: phone,
            failedAt: Date(), reason: .network))))
        let receipt = ConnectivityEnvelope(generation: envelope.generation, payload: .receipt(.init(attemptID: AttemptID(),
            noteID: watch.noteID, receivedAt: Date(), statusCode: 204)))
        let order = scenario == "receipt-first" ? [receipt, failure] : [failure, receipt]
        for message in order + [receipt] { receiver(.message(message)) }
        receiver(.message(.init(generation: envelope.generation,
            payload: .title(.init(noteID: watch.noteID, title: "Peer confirmed title", source: .transcription)))))
    }
    public func transferFile(at url: URL, metadata: ConnectivityEnvelope) throws {}
    public func updateContext(_ envelope: ConnectivityEnvelope, credentials: StoredWebhookCredentials?) throws {}
}
#endif
