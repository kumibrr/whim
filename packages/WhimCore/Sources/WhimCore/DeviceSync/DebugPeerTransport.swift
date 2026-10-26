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
    private var fixtureGeneration: ResetGeneration = .initial
    private var corruptFixture: URL?
    private var answeredAudioRequests: Set<UUID> = []
    private var isAudioSynchronizationScenario: Bool {
        ["pending-audio", "pending-sent", "sync-failure", "sync-repair"].contains(scenario)
    }
    public var isAvailable: Bool { scenario != "isolated" }
    public var isActivated: Bool { true }
    private init(scenario: String, fixture: URL) { self.scenario = scenario; self.fixture = fixture }
    public static func from(arguments: [String], fixture: URL) throws -> DebugPeerTransport? {
        guard let index = arguments.firstIndex(of: "-WhimPeerScenario") else {
            let fixtureFlags = ["-WhimFixtureAudio", "-WhimFixtureWebhookURL", "-WhimWatchTestID"]
            return arguments.contains(where: fixtureFlags.contains) ? .init(scenario: "isolated", fixture: fixture) : nil
        }
        guard arguments.indices.contains(index + 1),
              ["file-first", "state-first", "receipt-first", "failure-first", "interrupted-pending", "resend-interrupted",
               "pending-audio", "pending-sent", "sync-failure", "sync-repair"].contains(arguments[index + 1]) else {
            throw WhimServiceError.setupRequired("Unknown development peer scenario.")
        }
        let audio: URL
        if let audioIndex = arguments.firstIndex(of: "-WhimFixtureAudio"), arguments.indices.contains(audioIndex + 1) {
            audio = URL(fileURLWithPath: arguments[audioIndex + 1])
        } else { audio = fixture }
        return .init(scenario: arguments[index + 1], fixture: audio)
    }

    /// Fixture setup only: reproduce an interrupted old-build copy before normal launch recovery.
    /// Assertions remain at the installed application's UI and webhook boundaries.
    func prepare(root: URL) throws {
        guard scenario == "interrupted-pending" || scenario == "resend-interrupted" || isAudioSynchronizationScenario else { return }
        let database = root.appendingPathComponent("whim.sqlite")
        fixtureGeneration = try ConnectivityJournal(databaseURL: database).resetState().generation
        if scenario == "sync-failure" {
            let corrupted = root.appendingPathComponent("corrupt-peer-fixture.m4a")
            try Data("unreadable Watch audio".utf8).write(to: corrupted)
            corruptFixture = corrupted
        }
        guard scenario == "interrupted-pending" else { return }
        let metadata = interruptedMetadata()
        guard case .noteMetadata(let note) = metadata.payload else { return }
        let generationFolder = String(fixtureGeneration.counter) + "_" + fixtureGeneration.origin.uuidString
        let pending = root.appendingPathComponent("Peer").appendingPathComponent(generationFolder)
            .appendingPathComponent(note.id.rawValue.uuidString + ".m4a")
        try FileManager.default.createDirectory(at: pending.deletingLastPathComponent(), withIntermediateDirectories: true)
        let audio = try Data(contentsOf: fixture)
        try audio.prefix(audio.count / 3).write(to: pending)
        try metadata.encoded().write(to: pending.appendingPathExtension("plist"), options: .atomic)
        try ConnectivityInbox(databaseURL: database).capture(metadata.encoded())
    }

    private func interruptedMetadata(audioRequestID: UUID? = nil) -> ConnectivityEnvelope {
        .init(generation: fixtureGeneration, payload: .noteMetadata(.init(
            id: .init(rawValue: UUID(uuidString: "09000000-0000-0000-0000-000000000003")!),
            recordingSessionID: .init(rawValue: UUID(uuidString: "09000000-0000-0000-0000-000000000004")!),
            title: "Interrupted Watch Note", titleSource: .timestamp,
            createdAt: Date(timeIntervalSince1970: 1_790_000_000), duration: 10,
            source: .appleWatch, captureOutcome: .completed, requiresReview: false, audioRequestID: audioRequestID)))
    }

    public func activate(receive: @escaping @Sendable (PeerEvent) -> Void) {
        lock.withLock { receiver = receive }
        receive(.activated)
        if isAudioSynchronizationScenario {
            let metadata = interruptedMetadata()
            receive(.message(metadata))
            if scenario == "pending-sent", case .noteMetadata(let note) = metadata.payload {
                receive(.message(.init(generation: fixtureGeneration, payload: .receipt(.init(attemptID: AttemptID(),
                    noteID: note.id, receivedAt: Date(), statusCode: 204)))))
            }
            if let corruptFixture { receive(.file(corruptFixture, metadata)) }
            return
        }
        if scenario == "interrupted-pending" {
            let metadata = ConnectivityEnvelope(generation: fixtureGeneration, payload: .noteMetadata(.init(
                id: .init(rawValue: UUID(uuidString: "09000000-0000-0000-0000-000000000001")!),
                recordingSessionID: .init(rawValue: UUID(uuidString: "09000000-0000-0000-0000-000000000002")!),
                title: "New Watch Note", titleSource: .timestamp,
                createdAt: Date(timeIntervalSince1970: 1_790_000_001), duration: 10,
                source: .appleWatch, captureOutcome: .completed, requiresReview: false)))
            receive(.message(metadata))
            receive(.file(fixture, metadata))
            return
        }
        if scenario == "resend-interrupted" {
            let metadata = interruptedMetadata()
            receive(.message(metadata))
            receive(.file(fixture, metadata))
            return
        }
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
        if case .audioRequest(let request) = envelope.payload, scenario == "sync-failure" || scenario == "sync-repair" {
            let receiver = lock.withLock { () -> (@Sendable (PeerEvent) -> Void)? in
                guard answeredAudioRequests.insert(request.requestID).inserted else { return nil }
                return self.receiver
            }
            if let receiver {
                receiver(.file(corruptFixture ?? fixture, interruptedMetadata(audioRequestID: request.requestID)))
            }
            return
        }
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
