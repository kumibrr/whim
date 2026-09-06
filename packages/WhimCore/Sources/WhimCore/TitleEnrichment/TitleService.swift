import Foundation

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
        let fallback = TitleSnapshot(noteID: note.id, title: timestampTitle(note.createdAt), source: .timestamp)
        let resolution = TitleResolution()
        return await withCheckedContinuation { continuation in
            resolution.install(continuation)
            Task {
                do {
                    let transcript = try await transcriber.transcribe(audioAt: note.audioURL, locale: locale())
                    guard let title = Self.title(from: transcript) else {
                        resolution.resolve(fallback)
                        return
                    }
                    try await store.updateTitle(noteID: note.id, title: title, source: .transcription)
                    resolution.resolve(TitleSnapshot(noteID: note.id, title: title, source: .transcription))
                } catch {
                    resolution.resolve(fallback)
                }
            }
            Task {
                try? await sleep(Self.deliveryDeadline)
                resolution.resolve(fallback)
            }
        }
    }

    private static func title(from transcript: String) -> String? {
        let normalized = transcript.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }.joined(separator: " ")
        guard !normalized.isEmpty else { return nil }

        var candidate = ""
        var sentence: String?
        for character in normalized {
            candidate.append(character)
            if ".!?。！？".contains(character) {
                if isMeaningful(candidate) {
                    sentence = candidate
                    break
                }
                candidate = ""
            }
        }
        if sentence == nil, isMeaningful(candidate) { sentence = candidate }
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
