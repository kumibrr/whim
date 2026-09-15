import Foundation

/// Only non-secret protocol facts are eligible for durable inbox/outbox storage.
public struct ConnectivityEnvelope: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let messageID: UUID
    public let sentAt: Date
    public let payload: Payload
    public let generation: ResetGeneration

    public init(schemaVersion: Int = 1, messageID: UUID = UUID(), sentAt: Date = Date(), generation: ResetGeneration = .initial, payload: Payload) {
        self.schemaVersion = schemaVersion; self.messageID = messageID; self.sentAt = sentAt; self.payload = payload; self.generation = generation
    }
    public enum Payload: Codable, Equatable, Sendable {
        case noteMetadata(NoteTransfer)
        case attempt(AttemptTransfer)
        case receipt(Receipt)
        case title(TitleTransfer)
        case deletion(NoteID)
        case reset
        case configuration(ConfigurationRevision)
        case acknowledgement(AcknowledgementTransfer)
    }
    public func encoded() throws -> Data { try PropertyListEncoder().encode(self) }
    public static func decode(_ data: Data) throws -> Self {
        let value = try PropertyListDecoder().decode(Self.self, from: data)
        guard value.schemaVersion == 1 else { throw ConnectivityError.unsupportedSchema }
        return value
    }
}

public enum ConnectivityError: Error { case unsupportedSchema, invalidFile, invalidConfiguration, inactiveSession }

public struct NoteTransfer: Codable, Equatable, Sendable {
    public let id: NoteID
    public let recordingSessionID: RecordingSessionID
    public let title: String
    public let titleSource: TitleSource
    public let createdAt: Date
    public let duration: TimeInterval
    public let source: CaptureSource
    public let captureOutcome: CaptureOutcome
    public let requiresReview: Bool

    public init(id: NoteID, recordingSessionID: RecordingSessionID, title: String, titleSource: TitleSource,
                createdAt: Date, duration: TimeInterval, source: CaptureSource,
                captureOutcome: CaptureOutcome, requiresReview: Bool) {
        self.id = id; self.recordingSessionID = recordingSessionID; self.title = title
        self.titleSource = titleSource; self.createdAt = createdAt; self.duration = duration
        self.source = source; self.captureOutcome = captureOutcome; self.requiresReview = requiresReview
    }
    public init(_ note: Note) {
        self.init(id: note.id, recordingSessionID: note.recordingSessionID, title: note.title,
            titleSource: note.titleSource, createdAt: note.createdAt, duration: note.duration,
            source: note.source, captureOutcome: note.captureOutcome, requiresReview: note.requiresReview)
    }
    func finalized(audioURL: URL) -> FinalizedRecording {
        .init(id: id, recordingSessionID: recordingSessionID, title: title, titleSource: titleSource,
            createdAt: createdAt, duration: duration, source: source, captureOutcome: captureOutcome,
            requiresReview: requiresReview, audioURL: audioURL)
    }
}

public enum AttemptTransfer: Codable, Equatable, Sendable {
    case started(Attempt)
    case failed(AttemptFailure)
    var noteID: NoteID { switch self { case .started(let a): a.noteID; case .failed(let f): f.attempt.noteID } }
    var event: DeliveryEvent { switch self { case .started(let a): .attemptStarted(a); case .failed(let f): .attemptFailed(f) } }
}
public struct TitleTransfer: Codable, Equatable, Sendable {
    public let noteID: NoteID
    public let title: String
    public let source: TitleSource
    public init(noteID: NoteID, title: String, source: TitleSource) {
        self.noteID = noteID; self.title = title; self.source = source
    }
}

extension ConnectivityEnvelope.Payload {
    var noteID: NoteID? {
        switch self {
        case .noteMetadata(let n): n.id
        case .attempt(let a): a.noteID
        case .receipt(let r): r.noteID
        case .title(let t): t.noteID
        case .deletion(let id): id
        case .reset, .acknowledgement, .configuration: nil
        }
    }
}

public struct ResetGeneration: Codable, Equatable, Comparable, Sendable {
    public let counter: UInt64
    public let origin: UUID
    public static let initial = ResetGeneration(counter: 0, origin: UUID(uuidString: "00000000-0000-0000-0000-000000000000")!)
    public init(counter: UInt64, origin: UUID) { self.counter = counter; self.origin = origin }
    public static func < (lhs: Self, rhs: Self) -> Bool {
        (lhs.counter, lhs.origin.uuidString) < (rhs.counter, rhs.origin.uuidString)
    }
}
public enum AcknowledgementTransfer: Codable, Equatable, Sendable {
    case deletion(NoteID, AttemptDevice)
    case reset(AttemptDevice)
    case configuration(ConfigurationRevisionID)
    case durable(UUID)
}

extension ConnectivityEnvelope {
    var sanitized: Self {
        func endpoint(_ value: SanitizedEndpoint) -> SanitizedEndpoint {
            .init(scheme: value.scheme, host: value.host, port: value.port,
                path: String(value.path.prefix { $0 != "?" && $0 != "#" }))
        }
        func attempt(_ value: Attempt) -> Attempt {
            .init(id: value.id, noteID: value.noteID, configurationRevisionID: value.configurationRevisionID,
                device: value.device, endpoint: endpoint(value.endpoint), startedAt: value.startedAt, retryCycle: value.retryCycle)
        }
        let payload: Payload
        switch self.payload {
        case .attempt(.started(let value)): payload = .attempt(.started(attempt(value)))
        case .attempt(.failed(let value)):
            payload = .attempt(.failed(.init(attempt: attempt(value.attempt), failedAt: value.failedAt,
                reason: value.reason, retryAfter: value.retryAfter)))
        case .configuration(let value): payload = .configuration(.init(id: value.id, changedAt: value.changedAt, endpoint: endpoint(value.endpoint)))
        default: payload = self.payload
        }
        return .init(schemaVersion: schemaVersion, messageID: messageID, sentAt: sentAt, generation: generation, payload: payload)
    }
}
