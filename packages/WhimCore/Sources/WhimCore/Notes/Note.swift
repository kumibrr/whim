import Foundation

public struct NoteID: RawRepresentable, Codable, Hashable, Sendable {
    public let rawValue: UUID

    public init(rawValue: UUID) {
        self.rawValue = rawValue
    }

    public init() {
        self.init(rawValue: UUID())
    }
}

public enum CaptureSource: String, Codable, Sendable {
    case iphone
    case appleWatch = "apple_watch"
}

public enum TitleSource: String, Codable, Sendable {
    case transcription
    case timestamp
    case recovered
}

public enum CaptureOutcome: String, Codable, Sendable {
    case completed
    case interrupted
    case recovered
}

public enum NoteFilter: String, Codable, Sendable {
    case all
    case queued
    case failed
    case sent
}

public struct Note: Codable, Equatable, Sendable {
    public let id: NoteID
    public let recordingSessionID: RecordingSessionID
    public let title: String
    public let titleSource: TitleSource
    public let createdAt: Date
    public let duration: TimeInterval
    public let source: CaptureSource
    public let captureOutcome: CaptureOutcome
    public let requiresReview: Bool
    public let audioURL: URL
    public let workflowID: String
    public let delivery: Delivery

    public init(
        id: NoteID,
        recordingSessionID: RecordingSessionID,
        title: String,
        titleSource: TitleSource,
        createdAt: Date,
        duration: TimeInterval,
        source: CaptureSource,
        captureOutcome: CaptureOutcome,
        requiresReview: Bool,
        audioURL: URL,
        workflowID: String = WorkflowDefinition.default.id,
        delivery: Delivery = .pending
    ) {
        self.id = id
        self.recordingSessionID = recordingSessionID
        self.title = title
        self.titleSource = titleSource
        self.createdAt = createdAt
        self.duration = duration
        self.source = source
        self.captureOutcome = captureOutcome
        self.requiresReview = requiresReview
        self.audioURL = audioURL
        self.workflowID = workflowID
        self.delivery = delivery
    }
}

public struct FinalizedRecording: Codable, Equatable, Sendable {
    public let id: NoteID
    public let recordingSessionID: RecordingSessionID
    public let title: String
    public let titleSource: TitleSource
    public let createdAt: Date
    public let duration: TimeInterval
    public let source: CaptureSource
    public let captureOutcome: CaptureOutcome
    public let requiresReview: Bool
    public let audioURL: URL

    public init(
        id: NoteID,
        recordingSessionID: RecordingSessionID,
        title: String,
        titleSource: TitleSource,
        createdAt: Date,
        duration: TimeInterval,
        source: CaptureSource,
        captureOutcome: CaptureOutcome,
        requiresReview: Bool,
        audioURL: URL
    ) {
        self.id = id
        self.recordingSessionID = recordingSessionID
        self.title = title
        self.titleSource = titleSource
        self.createdAt = createdAt
        self.duration = duration
        self.source = source
        self.captureOutcome = captureOutcome
        self.requiresReview = requiresReview
        self.audioURL = audioURL
    }
}

public struct NoteProjection: Codable, Equatable, Sendable {
    public let id: NoteID
    public let title: String
    public let createdAt: Date
    public let duration: TimeInterval
    public let source: CaptureSource
    public let status: DeliveryStatus
    public let requiresReview: Bool
    public let hasLocalAudio: Bool

    public init(note: Note, hasLocalAudio: Bool = true) {
        id = note.id
        title = note.title
        createdAt = note.createdAt
        duration = note.duration
        source = note.source
        status = note.delivery.status
        requiresReview = note.requiresReview
        self.hasLocalAudio = hasLocalAudio
    }
}
