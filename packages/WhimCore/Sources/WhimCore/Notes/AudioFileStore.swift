import Foundation
import AVFoundation

public struct FinalizedAudio: Sendable {
    public let url: URL
    public let duration: TimeInterval
    public let createdAt: Date
}

public struct PartialAudio: Sendable {
    public let url: URL
    public let duration: TimeInterval
}

public protocol AudioFileManaging: Sendable {
    func deleteTemporary(sessionID: RecordingSessionID) throws
    func audioError(at url: URL) -> LocalAudioError?
    func durableNoteIDs() throws -> [NoteID]
    func durableAudio(noteID: NoteID) throws -> FinalizedAudio?
    func audioURL(for noteID: NoteID) -> URL
    func temporaryURL(for sessionID: RecordingSessionID) throws -> URL
    func finalize(sessionID: RecordingSessionID, noteID: NoteID) throws -> FinalizedAudio
    func makeDeliveredProtectionStrict(noteID: NoteID) throws
    func delete(noteID: NoteID) throws
    func playablePartial(sessionID: RecordingSessionID) throws -> PartialAudio?
}

public struct AudioFileStore: AudioFileManaging {
    private let root: URL
    private let durability: any FileDurability
    private let closeWriter: @Sendable (RecordingSessionID) throws -> Void

    /// The recording adapter must close its active writer synchronously in this callback.
    public init(root: URL, durability: any FileDurability = SystemFileDurability(),
                closeWriter: @escaping @Sendable (RecordingSessionID) throws -> Void) throws {
        self.root = root
        self.durability = durability
        self.closeWriter = closeWriter
        for name in ["Notes", "RecordingSessions"] {
            try FileManager.default.createDirectory(at: root.appendingPathComponent(name), withIntermediateDirectories: true)
            try durability.protect(root.appendingPathComponent(name), as: .unsent)
        }
    }

    public func temporaryURL(for sessionID: RecordingSessionID) throws -> URL {
        root.appendingPathComponent("RecordingSessions").appendingPathComponent(sessionID.rawValue.uuidString + ".m4a")
    }

    public func finalize(sessionID: RecordingSessionID, noteID: NoteID) throws -> FinalizedAudio {
        let temporary = try temporaryURL(for: sessionID)
        try closeWriter(sessionID)
        let audio = try AVAudioFile(forReading: temporary)
        let duration = Double(audio.length) / audio.processingFormat.sampleRate
        try durability.synchronizeFile(at: temporary)
        let destination = audioURL(for: noteID)
        try FileManager.default.moveItem(at: temporary, to: destination)
        try durability.protect(destination, as: .unsent)
        try durability.synchronizeDirectory(at: destination.deletingLastPathComponent())
        return FinalizedAudio(url: destination, duration: duration, createdAt: try destination.resourceValues(forKeys: [.creationDateKey]).creationDate ?? Date())
    }

    public func audioURL(for noteID: NoteID) -> URL {
        root.appendingPathComponent("Notes").appendingPathComponent(noteID.rawValue.uuidString + ".m4a")
    }

    public func audioError(at url: URL) -> LocalAudioError? {
        guard FileManager.default.fileExists(atPath: url.path) else { return .missing }
        do {
            let file = try AVAudioFile(forReading: url)
            guard file.length > 0 else { return .unreadable }
            let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 4_096)!
            while file.framePosition < file.length {
                try file.read(into: buffer)
                guard buffer.frameLength > 0 else { return .unreadable }
            }
            return nil
        } catch { return .unreadable }
    }

    public func durableNoteIDs() throws -> [NoteID] {
        try FileManager.default.contentsOfDirectory(at: root.appendingPathComponent("Notes"), includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "m4a" }
            .compactMap { UUID(uuidString: $0.deletingPathExtension().lastPathComponent).map { NoteID(rawValue: $0) } }
    }

    public func durableAudio(noteID: NoteID) throws -> FinalizedAudio? {
        let url = audioURL(for: noteID)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let file = try AVAudioFile(forReading: url)
        guard file.length > 0 else { return nil }
        try durability.synchronizeFile(at: url)
        try durability.protect(url, as: .unsent)
        try durability.synchronizeDirectory(at: url.deletingLastPathComponent())
        return FinalizedAudio(url: url, duration: Double(file.length) / file.processingFormat.sampleRate,
            createdAt: try url.resourceValues(forKeys: [.creationDateKey]).creationDate ?? Date())
    }

    public func finalize(_ recording: FinalizedRecording, in store: any WhimStore) async throws -> Note {
        do {
            let audio = try finalize(sessionID: recording.recordingSessionID, noteID: recording.id)
            return try await store.saveFinalized(FinalizedRecording(id: recording.id, recordingSessionID: recording.recordingSessionID,
                title: recording.title, titleSource: recording.titleSource, createdAt: recording.createdAt, duration: audio.duration,
                source: recording.source, captureOutcome: recording.captureOutcome, requiresReview: recording.requiresReview, audioURL: audio.url))
        } catch {
            let localError: LocalAudioError = (error as? POSIXError)?.code == .ENOSPC ? .storageFull : .durabilityFailure
            // If SQLite also has no space, preserve the original failure and leave the session for recovery.
            try? await store.recordSessionError(localError, sessionID: recording.recordingSessionID)
            throw error
        }
    }

    public func makeDeliveredProtectionStrict(noteID: NoteID) throws {
        try durability.protect(audioURL(for: noteID), as: .delivered)
    }
    public func delete(noteID: NoteID) throws {
        let url = audioURL(for: noteID)
        if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
        try durability.synchronizeDirectory(at: url.deletingLastPathComponent())
    }

    public func deleteTemporary(sessionID: RecordingSessionID) throws {
        let url = try temporaryURL(for: sessionID)
        if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
        try durability.synchronizeDirectory(at: url.deletingLastPathComponent())
    }
    public func playablePartial(sessionID: RecordingSessionID) throws -> PartialAudio? {
        let url = try temporaryURL(for: sessionID)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let file = try AVAudioFile(forReading: url)
        guard file.length > 0 else { return nil }
        return PartialAudio(url: url, duration: Double(file.length) / file.processingFormat.sampleRate)
    }
}
