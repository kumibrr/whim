#if canImport(Speech) && !os(watchOS)
import Foundation
import XCTest
@testable import WhimCore

final class OnDeviceTranscriberTests: XCTestCase {
    // Break: Cancellation can win before the continuation is installed, leaving transcription suspended forever.
    func testCancellationBeforeContinuationInstallStillCompletes() async {
        let recognizer = SpeechRecognizerFake()
        let transcriber = OnDeviceTranscriber(isAuthorized: { true }, makeRecognizer: { _ in recognizer })
        let completed = expectation(description: "cancelled transcription completes")
        let transcription = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            do {
                _ = try await transcriber.transcribe(
                    audioAt: URL(fileURLWithPath: "/tmp/cancelled.m4a"), locale: Locale(identifier: "en_US"))
                XCTFail("Cancelled transcription succeeded")
            } catch is CancellationError { }
            catch { XCTFail("Unexpected error: \(error)") }
            completed.fulfill()
        }

        await fulfillment(of: [completed], timeout: 0.5)
        transcription.cancel()
        XCTAssertEqual(recognizer.task.cancelCount, 1)
    }

    // Break: A synchronous final result arrives before the platform task is retained, leaking the task uncancelled.
    func testSynchronousCompletionCancelsTaskReturnedAfterTerminalResult() async throws {
        let recognizer = SpeechRecognizerFake(resultDuringStart: .success("Finished immediately"))
        let transcriber = OnDeviceTranscriber(isAuthorized: { true }, makeRecognizer: { _ in recognizer })

        let transcript = try await transcriber.transcribe(
            audioAt: URL(fileURLWithPath: "/tmp/immediate.m4a"), locale: Locale(identifier: "en_US"))

        XCTAssertEqual(transcript, "Finished immediately")
        XCTAssertEqual(recognizer.task.cancelCount, 1)
        XCTAssertTrue(recognizer.requiresOnDeviceRecognition)
    }
}

private final class SpeechRecognitionTaskFake: SpeechRecognitionTask, @unchecked Sendable {
    private let lock = NSLock()
    private var cancellations = 0

    var cancelCount: Int { lock.withLock { cancellations } }
    func cancel() { lock.withLock { cancellations += 1 } }
}

private final class SpeechRecognizerFake: SpeechRecognizer, @unchecked Sendable {
    let isAvailable = true
    let supportsOnDeviceRecognition = true
    let task = SpeechRecognitionTaskFake()
    private let resultDuringStart: Result<String, Error>?
    private let lock = NSLock()
    private var requiredOnDevice = false

    var requiresOnDeviceRecognition: Bool { lock.withLock { requiredOnDevice } }

    init(resultDuringStart: Result<String, Error>? = nil) {
        self.resultDuringStart = resultDuringStart
    }

    func startRecognition(audioAt url: URL, requiresOnDeviceRecognition: Bool,
        completion: @escaping @Sendable (Result<String, Error>) -> Void) -> any SpeechRecognitionTask {
        lock.withLock { requiredOnDevice = requiresOnDeviceRecognition }
        if let resultDuringStart { completion(resultDuringStart) }
        return task
    }
}
#endif
