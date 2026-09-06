#if canImport(Speech) && !os(watchOS)
import Foundation
import Speech

/// Speech adapter that rejects every path that could require Apple's servers.
public final class OnDeviceTranscriber: Transcriber, @unchecked Sendable {
    public init() {}

    public func transcribe(audioAt url: URL, locale: Locale) async throws -> String {
        guard SFSpeechRecognizer.authorizationStatus() == .authorized else {
            throw TranscriptionError.notAuthorized
        }
        guard let recognizer = SFSpeechRecognizer(locale: locale),
              recognizer.isAvailable,
              recognizer.supportsOnDeviceRecognition else {
            throw TranscriptionError.unavailable
        }

        let request = SFSpeechURLRecognitionRequest(url: url)
        request.shouldReportPartialResults = false
        request.requiresOnDeviceRecognition = true
        let resolution = SpeechResolution()

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                resolution.install(continuation)
                let task = recognizer.recognitionTask(with: request) { result, error in
                    if let error {
                        resolution.fail(error)
                    } else if let result, result.isFinal {
                        resolution.succeed(result.bestTranscription.formattedString)
                    }
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
    private var task: SFSpeechRecognitionTask?
    private var finished = false

    func install(_ continuation: CheckedContinuation<String, Error>) {
        lock.withLock { self.continuation = continuation }
    }

    func retain(_ task: SFSpeechRecognitionTask) {
        lock.withLock { self.task = task }
    }

    func succeed(_ transcript: String) { finish(with: .success(transcript)) }

    func fail(_ error: Error) { finish(with: .failure(error)) }

    func cancel() {
        let task = lock.withLock { self.task }
        task?.cancel()
        finish(with: .failure(CancellationError()))
    }

    private func finish(with result: Result<String, Error>) {
        let continuation = lock.withLock { () -> CheckedContinuation<String, Error>? in
            guard !finished else { return nil }
            finished = true
            task = nil
            let continuation = self.continuation
            self.continuation = nil
            return continuation
        }
        continuation?.resume(with: result)
    }
}
#endif
