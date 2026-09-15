#if DEBUG
import AVFoundation
import Foundation

/// Deterministic microphone boundary for compiled development journeys only.
public actor DebugFixtureRecorder: AudioRecorder {
    private let fixture: URL
    private let pair = AsyncStream.makeStream(of: RecordingEvent.self)
    private var timer: Task<Void, Never>?
    public init(fixture: URL) { self.fixture = fixture }
    public static func from(arguments: [String]) throws -> DebugFixtureRecorder? {
        guard let index = arguments.firstIndex(of: "-WhimFixtureAudio") else { return nil }
        guard arguments.indices.contains(index + 1), arguments[index + 1].hasPrefix("/"),
              FileManager.default.isReadableFile(atPath: arguments[index + 1]) else {
            throw WhimServiceError.setupRequired("The development audio fixture is unavailable.")
        }
        return .init(fixture: URL(fileURLWithPath: arguments[index + 1]))
    }
    public func events() -> AsyncStream<RecordingEvent> { pair.stream }
    public func start(at url: URL) throws {
        try FileManager.default.copyItem(at: fixture, to: url)
        let continuation = pair.continuation
        timer = Task {
            let start = Date()
            while !Task.isCancelled {
                continuation.yield(.elapsed(Date().timeIntervalSince(start)))
                continuation.yield(.peakPower(-12))
                do { try await Task.sleep(for: .milliseconds(100)) } catch { return }
            }
        }
    }
    public func stop() async throws {
        timer?.cancel(); timer = nil
        let duration = try await AVURLAsset(url: fixture).load(.duration).seconds
        pair.continuation.yield(.encoderCompleted(duration: duration, peakPowerDBFS: -12))
    }
    public func discard() { timer?.cancel(); timer = nil }
}
#endif
