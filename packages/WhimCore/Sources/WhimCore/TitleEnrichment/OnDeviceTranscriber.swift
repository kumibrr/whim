#if canImport(Speech) && !os(watchOS)
import Foundation
import Speech

/// Minimal boundary for the lifetime of a Speech recognition request.
public protocol SpeechRecognitionTask: AnyObject, Sendable {
    func cancel()
}

/// Injectable boundary around `SFSpeechRecognizer`; production always requests local recognition.
public protocol SpeechRecognizer: AnyObject, Sendable {
    var isAvailable: Bool { get }
    var supportsOnDeviceRecognition: Bool { get }
    func startRecognition(
        audioAt url: URL,
        requiresOnDeviceRecognition: Bool,
        completion: @escaping @Sendable (Result<String, Error>) -> Void
    ) -> any SpeechRecognitionTask
}

public typealias SpeechRecognizerFactory = @Sendable (Locale) -> (any SpeechRecognizer)?

/// Speech adapter that rejects every path that could require Apple's servers.
public final class OnDeviceTranscriber: Transcriber, @unchecked Sendable {
    private let isAuthorized: @Sendable () -> Bool
    private let makeRecognizer: SpeechRecognizerFactory

    public convenience init() {
        self.init(
            isAuthorized: { SFSpeechRecognizer.authorizationStatus() == .authorized },
            makeRecognizer: { locale in SFSpeechRecognizer(locale: locale).map(AppleSpeechRecognizer.init) }
        )
    }

    public init(
        isAuthorized: @escaping @Sendable () -> Bool,
        makeRecognizer: @escaping SpeechRecognizerFactory
    ) {
        self.isAuthorized = isAuthorized
        self.makeRecognizer = makeRecognizer
    }

    public func transcribe(audioAt url: URL, locale: Locale) async throws -> String {
        guard isAuthorized() else { throw TranscriptionError.notAuthorized }
        guard let recognizer = makeRecognizer(locale),
              recognizer.isAvailable,
              recognizer.supportsOnDeviceRecognition else {
            throw TranscriptionError.unavailable
        }

        let resolution = SpeechResolution()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                resolution.install(continuation)
                let task = recognizer.startRecognition(audioAt: url, requiresOnDeviceRecognition: true) {
                    resolution.finish(with: $0)
                }
                resolution.retain(task)
            }
        } onCancel: {
            resolution.cancel()
        }
    }
}

private final class SpeechResolution: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<String, Error>?
    private var task: (any SpeechRecognitionTask)?
    private var terminalResult: Result<String, Error>?

    func install(_ continuation: CheckedContinuation<String, Error>) {
        let terminalResult = lock.withLock { () -> Result<String, Error>? in
            if let terminalResult { return terminalResult }
            self.continuation = continuation
            return nil
        }
        if let terminalResult { continuation.resume(with: terminalResult) }
    }

    func retain(_ task: any SpeechRecognitionTask) {
        let shouldCancel = lock.withLock { () -> Bool in
            guard terminalResult == nil else { return true }
            self.task = task
            return false
        }
        if shouldCancel { task.cancel() }
    }

    func cancel() { finish(with: .failure(CancellationError())) }

    func finish(with result: Result<String, Error>) {
        let terminal = lock.withLock {
            () -> (CheckedContinuation<String, Error>?, (any SpeechRecognitionTask)?)? in
            guard terminalResult == nil else { return nil }
            terminalResult = result
            let terminal = (continuation, task)
            continuation = nil
            task = nil
            return terminal
        }
        guard let (continuation, task) = terminal else { return }
        task?.cancel()
        continuation?.resume(with: result)
    }
}

private final class AppleSpeechRecognizer: SpeechRecognizer, @unchecked Sendable {
    private let recognizer: SFSpeechRecognizer

    init(_ recognizer: SFSpeechRecognizer) { self.recognizer = recognizer }

    var isAvailable: Bool { recognizer.isAvailable }
    var supportsOnDeviceRecognition: Bool { recognizer.supportsOnDeviceRecognition }

    func startRecognition(audioAt url: URL, requiresOnDeviceRecognition: Bool,
        completion: @escaping @Sendable (Result<String, Error>) -> Void) -> any SpeechRecognitionTask {
        let request = SFSpeechURLRecognitionRequest(url: url)
        request.shouldReportPartialResults = false
        request.requiresOnDeviceRecognition = requiresOnDeviceRecognition
        let task = recognizer.recognitionTask(with: request) { result, error in
            if let error {
                completion(.failure(error))
            } else if let result, result.isFinal {
                completion(.success(result.bestTranscription.formattedString))
            }
        }
        return AppleSpeechRecognitionTask(task)
    }
}

private final class AppleSpeechRecognitionTask: SpeechRecognitionTask, @unchecked Sendable {
    private let task: SFSpeechRecognitionTask
    init(_ task: SFSpeechRecognitionTask) { self.task = task }
    func cancel() { task.cancel() }
}
#endif
