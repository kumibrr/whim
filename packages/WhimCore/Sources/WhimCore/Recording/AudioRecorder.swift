import Foundation

public enum RecordingEvent: Sendable, Equatable {
    case elapsed(TimeInterval)
    case peakPower(Float)
    case signal(RecordingSignal)
    case interruption
    case routeChanged
    case encoderCompleted(duration: TimeInterval, peakPowerDBFS: Float)
    case failure
}

public protocol AudioRecorder: Sendable {
    func events() async -> AsyncStream<RecordingEvent>
    func start(at url: URL) async throws
    func stop() async throws
    func discard() async
}
