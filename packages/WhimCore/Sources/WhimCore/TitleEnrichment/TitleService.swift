import Foundation
import NaturalLanguage

public struct TitleSnapshot: Sendable, Equatable {
    public let noteID: NoteID
    public let title: String
    public let source: TitleSource

    public init(noteID: NoteID, title: String, source: TitleSource) {
        self.noteID = noteID
        self.title = title
        self.source = source
    }
}

public struct TitleService: Sendable {
    public static let deliveryDeadline: Duration = .milliseconds(300)

    private let transcriber: any Transcriber
    private let store: any WhimStore
    private let locale: @Sendable () -> Locale
    private let timestampTitle: @Sendable (Date) -> String
    private let sleep: @Sendable (Duration) async throws -> Void
    private let jobs = TitleJobs()

    public init(
        transcriber: any Transcriber,
        store: any WhimStore,
        locale: @escaping @Sendable () -> Locale = { .current },
        timestampTitle: @escaping @Sendable (Date) -> String = {
            $0.formatted(date: .abbreviated, time: .shortened)
        },
        sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    ) {
        self.transcriber = transcriber
        self.store = store
        self.locale = locale
        self.timestampTitle = timestampTitle
        self.sleep = sleep
    }

    /// Returns the immutable metadata available to delivery at 300 ms. Recognition keeps
    /// running after that deadline and may update only the local Note title.
    public func enrich(_ note: Note) async -> TitleSnapshot {
        let fallback = fallback(for: note)
        let job = await jobs.job(for: note.id) { await produceFinalSnapshot(note, fallback: fallback) }
        let resolution = TitleResolution()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                resolution.install(continuation)
                Task { resolution.resolve(await job.value) }
                Task {
                    try? await sleep(Self.deliveryDeadline)
                    resolution.resolve(fallback)
                }
            }
        } onCancel: {
            resolution.resolve(fallback)
        }
    }

    /// Joins the shared transcription job through its final local persistence. The façade uses
    /// this to publish the late title update without creating a second recognition request.
    public func complete(_ note: Note) async -> TitleSnapshot {
        let fallback = fallback(for: note)
        return await jobs.job(for: note.id) {
            await produceFinalSnapshot(note, fallback: fallback)
        }.value
    }

    public func cancel(noteID: NoteID) async { await jobs.cancel(noteID: noteID) }

    private func fallback(for note: Note) -> TitleSnapshot {
        TitleSnapshot(noteID: note.id, title: timestampTitle(note.createdAt), source: .timestamp)
    }

    private func produceFinalSnapshot(_ note: Note, fallback: TitleSnapshot) async -> TitleSnapshot {
        do {
            let transcript = try await transcriber.transcribe(audioAt: note.audioURL, locale: locale())
            guard !Task.isCancelled, let title = Self.title(from: transcript) else { return fallback }
            try await store.updateTitle(noteID: note.id, title: title, source: .transcription)
            return TitleSnapshot(noteID: note.id, title: title, source: .transcription)
        } catch {
            return fallback
        }
    }

    private static func title(from transcript: String) -> String? {
        let normalized = transcript.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }.joined(separator: " ")
        guard !normalized.isEmpty else { return nil }

        var sentence: String?
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = normalized
        tokenizer.enumerateTokens(in: normalized.startIndex..<normalized.endIndex) { range, _ in
            let candidate = String(normalized[range]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard isMeaningful(candidate) else { return true }
            sentence = candidate
            return false
        }
        guard let sentence else { return nil }
        return String(sentence.trimmingCharacters(in: .whitespacesAndNewlines).prefix(60))
    }

    private static func isMeaningful(_ text: String) -> Bool {
        text.unicodeScalars.contains {
            !CharacterSet.whitespacesAndNewlines.contains($0)
                && !CharacterSet.punctuationCharacters.contains($0)
        }
    }
}

private actor TitleJobs {
    private var tasks: [NoteID: Task<TitleSnapshot, Never>] = [:]

    func job(for noteID: NoteID,
             operation: @escaping @Sendable () async -> TitleSnapshot) -> Task<TitleSnapshot, Never> {
        if let existing = tasks[noteID] { return existing }
        let task = Task { await operation() }
        tasks[noteID] = task
        return task
    }

    func cancel(noteID: NoteID) async {
        guard let task = tasks.removeValue(forKey: noteID) else { return }
        task.cancel()
        _ = await task.value
    }
}

private final class TitleResolution: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<TitleSnapshot, Never>?
    private var value: TitleSnapshot?

    func install(_ continuation: CheckedContinuation<TitleSnapshot, Never>) {
        let value = lock.withLock { () -> TitleSnapshot? in
            if let value { return value }
            self.continuation = continuation
            return nil
        }
        if let value { continuation.resume(returning: value) }
    }

    func resolve(_ value: TitleSnapshot) {
        let continuation = lock.withLock { () -> CheckedContinuation<TitleSnapshot, Never>? in
            guard self.value == nil else { return nil }
            self.value = value
            let continuation = self.continuation
            self.continuation = nil
            return continuation
        }
        continuation?.resume(returning: value)
    }
}
