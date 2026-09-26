import Foundation

public struct StartupProjection: Equatable, Sendable {
    public let onboardingCompleted: Bool
    public let microphone: PermissionStatus
    public let recording: RecordingProjection?
    public init(onboardingCompleted: Bool, microphone: PermissionStatus, recording: RecordingProjection?) {
        self.onboardingCompleted = onboardingCompleted; self.microphone = microphone; self.recording = recording
    }
}

public protocol WhimClient: Sendable {
    func startup() async throws -> StartupProjection
    func maintain() async throws
    func startRecording(source: CaptureSource) async throws -> RecordingProjection
    func activeRecording() async throws -> RecordingProjection?
    func stopRecording() async throws -> NoteProjection?
    func discardRecording() async throws
    func listNotes(filter: NoteFilter) async throws -> [NoteProjection]
    func note(id: NoteID) async throws -> NoteDetailProjection?
    func retry(noteID: NoteID) async throws
    func retryAllFailed() async throws -> Int
    func sendRecovered(noteID: NoteID) async throws
    func delete(noteID: NoteID) async throws
    func updateWebhook(_ input: WebhookConfigurationInput) async throws -> ConfigurationUpdateResult
    func testWebhook() async throws -> ConfigurationTestResult
    func updatePreferences(_ input: PreferenceInput) async throws
    func settings() async throws -> SettingsProjection
    func completeOnboarding() async throws
    func requestPermission(_ kind: PermissionKind) async throws -> PermissionStatus
    func openSystemSettings() async throws
    func waveform(noteID: NoteID) async throws -> AudioWaveform
    func playNote(_ id: NoteID) async throws -> PlaybackProjection
    func stopPlayback() async
    func playbackSnapshot() async -> PlaybackProjection?
    func patchWebhook(_ patch: WebhookPatch) async throws -> ConfigurationUpdateResult
    /// Failed webhook Attempts across local Notes, newest first.
    func webhookErrors() async throws -> [WebhookErrorProjection]
    func reset() async throws
    func events() -> AsyncStream<WhimEvent>
}

public extension WhimClient {
    func maintain() async throws {}
    func startup() async throws -> StartupProjection {
        let settings = try await settings()
        return try await StartupProjection(onboardingCompleted: settings.onboardingCompleted,
            microphone: settings.permissions.microphone, recording: activeRecording())
    }
    func waveform(noteID: NoteID) async throws -> AudioWaveform { .unavailable }
    func playNote(_ id: NoteID) async throws -> PlaybackProjection { throw WhimServiceError.audioUnavailable }
    func stopPlayback() async {}
    func playbackSnapshot() async -> PlaybackProjection? { nil }
    func requestPermission(_ kind: PermissionKind) async throws -> PermissionStatus { throw WhimServiceError.setupRequired("Permissions unavailable.") }
    func openSystemSettings() async throws { throw WhimServiceError.setupRequired("System settings unavailable.") }
    func completeOnboarding() async throws { throw WhimServiceError.setupRequired("Onboarding unavailable.") }
    func settings() async throws -> SettingsProjection { throw WhimServiceError.setupRequired("Settings unavailable.") }
    func patchWebhook(_ patch: WebhookPatch) async throws -> ConfigurationUpdateResult { throw WhimServiceError.setupRequired("Settings unavailable.") }
    func webhookErrors() async throws -> [WebhookErrorProjection] { [] }
}

public struct RecordingProjection: Codable, Equatable, Sendable {
    public let schemaVersion = WhimCoreVersion.schema
    public let maximumDurationSeconds = Double(RecordingLimits.maximumDuration.components.seconds)
    public let warningLeadSeconds = Double(RecordingLimits.warningLeadTime.components.seconds)
    public let sessionID: String
    public let noteID: String
    public let source: CaptureSource
    public let createdAt: Date

    public init(_ snapshot: RecordingSnapshot) {
        sessionID = snapshot.sessionID.rawValue.uuidString.lowercased()
        noteID = snapshot.noteID.rawValue.uuidString.lowercased()
        source = snapshot.source
        createdAt = snapshot.createdAt
    }

    public init(schemaVersion: Int = WhimCoreVersion.schema, sessionID: String, noteID: String,
                source: CaptureSource, createdAt: Date) {
        self.sessionID = sessionID; self.noteID = noteID; self.source = source; self.createdAt = createdAt
    }

    private enum CodingKeys: String, CodingKey { case schemaVersion, sessionID, noteID, source, createdAt, maximumDurationSeconds, warningLeadSeconds }
}

public struct AttemptProjection: Codable, Equatable, Sendable {
    public enum Outcome: String, Codable, Sendable { case sending, failed, sent }
    public let id: String
    public let configurationRevisionID: String
    public let device: CaptureSource
    public let startedAt: Date
    public let destination: SanitizedEndpointProjection
    public let outcome: Outcome
    public let failureReason: String?
    public let responseStatusCode: Int?

    private enum CodingKeys: String, CodingKey {
        case id, configurationRevisionID, device, startedAt, destination, outcome
        case failureReason, responseStatusCode
    }
    public func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(id, forKey: .id); try values.encode(configurationRevisionID, forKey: .configurationRevisionID)
        try values.encode(device, forKey: .device); try values.encode(startedAt, forKey: .startedAt)
        try values.encode(destination, forKey: .destination); try values.encode(outcome, forKey: .outcome)
        try values.encode(failureReason, forKey: .failureReason)
        try values.encode(responseStatusCode, forKey: .responseStatusCode)
    }
}

public struct SanitizedEndpointProjection: Codable, Equatable, Sendable {
    public let scheme: String
    public let host: String
    public let port: Int?
    public let path: String
    public init(_ endpoint: SanitizedEndpoint) {
        scheme = endpoint.scheme; host = endpoint.host; port = endpoint.port; path = endpoint.path
    }
    private enum CodingKeys: String, CodingKey { case scheme, host, port, path }
    public func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(scheme, forKey: .scheme); try values.encode(host, forKey: .host)
        try values.encode(port, forKey: .port); try values.encode(path, forKey: .path)
    }
}

public struct NoteDetailProjection: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let id: String
    public let title: String
    public let createdAt: Date
    public let durationSeconds: TimeInterval
    public let source: CaptureSource
    public let status: DeliveryStatus
    public let requiresReview: Bool
    public let hasLocalAudio: Bool
    public let localError: LocalAudioError?
    public let workflowError: DeliveryWorkflowError?
    public let attempts: [AttemptProjection]

    public init(note: Note, hasLocalAudio: Bool = true, deliveryAttempts: [Attempt]? = nil) {
        let summary = NoteProjection(note: note, hasLocalAudio: hasLocalAudio)
        schemaVersion = summary.schemaVersion; id = summary.id.rawValue.uuidString.lowercased()
        title = summary.title; createdAt = summary.createdAt; durationSeconds = summary.duration
        source = summary.source; status = summary.status; requiresReview = summary.requiresReview
        self.hasLocalAudio = summary.hasLocalAudio; localError = summary.localError
        workflowError = summary.workflowError
        let sourceAttempts = deliveryAttempts
            ?? (note.delivery.activeAttempts + note.delivery.failedAttempts.map(\.attempt))
        let values = sourceAttempts.compactMap { attempt -> AttemptProjection? in
            if let receipt = note.delivery.receipt, receipt.attemptID == attempt.id {
                return Self.project(attempt, outcome: .sent, responseStatusCode: receipt.statusCode)
            }
            if let failure = note.delivery.failedAttempts.first(where: { $0.attempt.id == attempt.id }) {
                return Self.project(attempt, outcome: .failed, failureReason: failure.reason.externalRawValue,
                    responseStatusCode: failure.reason.statusCode)
            }
            guard note.delivery.activeAttempts.contains(where: { $0.id == attempt.id }) else { return nil }
            return Self.project(attempt, outcome: .sending)
        }
        attempts = values.sorted { $0.startedAt < $1.startedAt }
    }

    private static func project(_ attempt: Attempt, outcome: AttemptProjection.Outcome,
                                failureReason: String? = nil, responseStatusCode: Int? = nil) -> AttemptProjection {
        AttemptProjection(id: attempt.id.rawValue.uuidString.lowercased(),
            configurationRevisionID: attempt.configurationRevisionID.rawValue.uuidString.lowercased(),
            device: attempt.device == .iphone ? .iphone : .appleWatch, startedAt: attempt.startedAt,
            destination: .init(attempt.endpoint), outcome: outcome, failureReason: failureReason,
            responseStatusCode: responseStatusCode)
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, id, title, createdAt, durationSeconds, source, status
        case requiresReview, hasLocalAudio, localError, workflowError, attempts
    }
    public func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(schemaVersion, forKey: .schemaVersion); try values.encode(id, forKey: .id)
        try values.encode(title, forKey: .title); try values.encode(createdAt, forKey: .createdAt)
        try values.encode(durationSeconds, forKey: .durationSeconds); try values.encode(source, forKey: .source)
        try values.encode(status, forKey: .status); try values.encode(requiresReview, forKey: .requiresReview)
        try values.encode(hasLocalAudio, forKey: .hasLocalAudio); try values.encode(localError, forKey: .localError)
        try values.encode(workflowError, forKey: .workflowError)
        try values.encode(attempts, forKey: .attempts)
    }
}

/// One failed webhook Attempt and the message the destination returned, if any.
public struct WebhookErrorProjection: Codable, Equatable, Sendable {
    public let attemptID: String
    public let noteID: String
    public let noteTitle: String
    public let device: CaptureSource
    public let failedAt: Date
    public let destination: SanitizedEndpointProjection
    public let failureReason: String
    public let responseStatusCode: Int?
    /// The sanitized, capped response excerpt; nil when no response body was received.
    public let message: String?

    public init(note: Note, failure: AttemptFailure) {
        attemptID = failure.attempt.id.rawValue.uuidString.lowercased()
        noteID = note.id.rawValue.uuidString.lowercased(); noteTitle = note.title
        device = failure.attempt.device == .iphone ? .iphone : .appleWatch
        failedAt = failure.failedAt; destination = .init(failure.attempt.endpoint)
        failureReason = failure.reason.externalRawValue; responseStatusCode = failure.reason.statusCode
        message = failure.responseExcerpt
    }

    private enum CodingKeys: String, CodingKey {
        case attemptID, noteID, noteTitle, device, failedAt, destination, failureReason, responseStatusCode, message
    }
    public func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(attemptID, forKey: .attemptID); try values.encode(noteID, forKey: .noteID)
        try values.encode(noteTitle, forKey: .noteTitle); try values.encode(device, forKey: .device)
        try values.encode(failedAt, forKey: .failedAt); try values.encode(destination, forKey: .destination)
        try values.encode(failureReason, forKey: .failureReason)
        try values.encode(responseStatusCode, forKey: .responseStatusCode); try values.encode(message, forKey: .message)
    }
}

extension AttemptFailureReason {
    var externalRawValue: String {
        switch self { case .network: "network"; case .httpStatus: "http_status" }
    }
    var statusCode: Int? {
        if case .httpStatus(let value) = self { value } else { nil }
    }
}

public struct WebhookProjection: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let revisionID: String
    public let destination: SanitizedEndpointProjection
    public let customHeaderNames: [String]
    public init(revisionID: String, destination: SanitizedEndpointProjection, customHeaderNames: [String]) {
        schemaVersion = WhimCoreVersion.schema; self.revisionID = revisionID
        self.destination = destination; self.customHeaderNames = customHeaderNames
    }
}

public struct ConfigurationUpdateResult: Codable, Equatable, Sendable {
    public let revisionID: String
    public let failedCount: Int
    public let setupRequiredCount: Int
    public init(revisionID: ConfigurationRevisionID, failedCount: Int, setupRequiredCount: Int) {
        self.revisionID = revisionID.rawValue.uuidString.lowercased()
        self.failedCount = failedCount; self.setupRequiredCount = setupRequiredCount
    }
}

public struct PreferenceInput: Equatable, Sendable {
    public let retentionPolicy: RetentionPolicy
    public let transcriptionEnabled: Bool
    public let transcriptionLocaleIdentifier: String?
    public init(retentionPolicy: RetentionPolicy, transcriptionEnabled: Bool,
                transcriptionLocaleIdentifier: String?) {
        self.retentionPolicy = retentionPolicy; self.transcriptionEnabled = transcriptionEnabled
        self.transcriptionLocaleIdentifier = transcriptionLocaleIdentifier
    }
    public static let `default` = PreferenceInput(retentionPolicy: .thirtyDays,
        transcriptionEnabled: true, transcriptionLocaleIdentifier: nil)
}

extension PreferenceInput: Codable {
    private enum CodingKeys: String, CodingKey {
        case retentionPolicy, transcriptionEnabled, transcriptionLocaleIdentifier
    }
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let raw = try values.decode(String.self, forKey: .retentionPolicy)
        guard let policy = RetentionPolicy(externalRawValue: raw) else {
            throw DecodingError.dataCorruptedError(forKey: .retentionPolicy, in: values,
                debugDescription: "Unknown retention policy")
        }
        self.init(retentionPolicy: policy,
            transcriptionEnabled: try values.decode(Bool.self, forKey: .transcriptionEnabled),
            transcriptionLocaleIdentifier: try values.decodeIfPresent(String.self,
                forKey: .transcriptionLocaleIdentifier))
    }
    public func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(retentionPolicy.externalRawValue, forKey: .retentionPolicy)
        try values.encode(transcriptionEnabled, forKey: .transcriptionEnabled)
        try values.encode(transcriptionLocaleIdentifier, forKey: .transcriptionLocaleIdentifier)
    }
}

public extension RetentionPolicy {
    var externalRawValue: String {
        switch self {
        case .immediately: "immediately"; case .oneDay: "one_day"; case .sevenDays: "seven_days"
        case .thirtyDays: "thirty_days"; case .ninetyDays: "ninety_days"; case .never: "never"
        }
    }
    init?(externalRawValue: String) {
        switch externalRawValue {
        case "immediately": self = .immediately; case "one_day": self = .oneDay
        case "seven_days": self = .sevenDays; case "thirty_days": self = .thirtyDays
        case "ninety_days": self = .ninetyDays; case "never": self = .never
        default: return nil
        }
    }
}

public protocol PreferenceStoring: Sendable {
    func load() async throws -> PreferenceInput
    func save(_ input: PreferenceInput) async throws
    func reset() async throws
}

public struct WhimEvent: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case recordingStarted = "recording.started"
        case recordingProgress = "recording.progress"
        case recordingStopped = "recording.stopped"
        case recordingDiscarded = "recording.discarded"
        case recordingRouteChanged = "recording.route_changed"
        case recordingMaximumDurationWarning = "recording.maximum_duration_warning"
        case noteChanged = "note.changed"
        case noteDeleted = "note.deleted"
        case notesReset = "notes.reset"
        case settingsChanged = "settings.changed"
    }
    public let schemaVersion: Int
    public let sequence: UInt64
    public let type: Kind
    public let recording: RecordingProjection?
    public let note: NoteProjection?
    public let noteID: String?
    public let elapsedSeconds: TimeInterval?
    public let peakPowerDBFS: Float?
    public let recordingTone: Float?

    public init(sequence: UInt64, type: Kind, recording: RecordingProjection? = nil,
                note: NoteProjection? = nil, noteID: String? = nil,
                elapsedSeconds: TimeInterval? = nil, peakPowerDBFS: Float? = nil, recordingTone: Float? = nil) {
        schemaVersion = WhimCoreVersion.schema; self.sequence = sequence; self.type = type
        self.recording = recording; self.note = note; self.noteID = noteID
        self.elapsedSeconds = elapsedSeconds; self.peakPowerDBFS = peakPowerDBFS
        self.recordingTone = recordingTone
    }
}
