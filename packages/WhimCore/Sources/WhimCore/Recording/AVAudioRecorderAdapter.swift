import AVFoundation
import Foundation

public enum AVAudioRecorderAdapterError: Error, Sendable {
    case couldNotStart
}

/// The platform microphone boundary. AVFoundation owns encoding and closes the AAC writer
/// before `encoderCompleted` is emitted.
public final class AVAudioRecorderAdapter: NSObject, AudioRecorder, AVAudioRecorderDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private let eventStream: AsyncStream<RecordingEvent>
    private let continuation: AsyncStream<RecordingEvent>.Continuation
    private var recorder: AVAudioRecorder?
    private var meterTask: Task<Void, Never>?
    private var maximumPeakPowerDBFS: Float = -160
    private var notificationTokens: [NSObjectProtocol] = []

    public override init() {
        let pair = AsyncStream.makeStream(of: RecordingEvent.self)
        eventStream = pair.stream
        continuation = pair.continuation
        super.init()
        installAudioSessionNotifications()
    }

    deinit {
        meterTask?.cancel()
        for token in notificationTokens { NotificationCenter.default.removeObserver(token) }
        continuation.finish()
    }

    public func events() async -> AsyncStream<RecordingEvent> { eventStream }

    public func start(at url: URL) async throws {
        #if os(iOS) || os(watchOS)
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .spokenAudio)
        try session.setActive(true)
        #endif

        do {
            let audioRecorder = try AVAudioRecorder(url: url, settings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 16_000,
                AVNumberOfChannelsKey: 1,
                AVEncoderBitRateKey: 64_000,
                AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
            ])
            audioRecorder.delegate = self
            audioRecorder.isMeteringEnabled = true
            guard audioRecorder.prepareToRecord(), audioRecorder.record() else {
                throw AVAudioRecorderAdapterError.couldNotStart
            }
            lock.withLock {
                recorder = audioRecorder
                maximumPeakPowerDBFS = -160
            }
            beginMetering()
        } catch {
            deactivateAudioSession()
            throw error
        }
    }

    public func stop() async throws {
        let current = lock.withLock { recorder }
        guard let current else { throw AVAudioRecorderAdapterError.couldNotStart }
        stopMetering()
        current.stop()
    }

    public func discard() async {
        let current = lock.withLock { () -> AVAudioRecorder? in
            let current = recorder
            recorder = nil
            return current
        }
        stopMetering()
        current?.stop()
        _ = current?.deleteRecording()
        deactivateAudioSession()
    }

    public func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        stopMetering()
        let peak = lock.withLock { () -> Float in
            self.recorder = nil
            return maximumPeakPowerDBFS
        }
        deactivateAudioSession()
        if flag {
            continuation.yield(.encoderCompleted(duration: recorder.currentTime, peakPowerDBFS: peak))
        } else {
            continuation.yield(.failure)
        }
    }

    public func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: Error?) {
        stopMetering()
        continuation.yield(.failure)
    }

    private func beginMetering() {
        meterTask?.cancel()
        meterTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(100))
                guard !Task.isCancelled else { return }
                self?.sampleMeters()
            }
        }
    }

    private func stopMetering() {
        lock.withLock {
            meterTask?.cancel()
            meterTask = nil
        }
    }

    private func sampleMeters() {
        let sample = lock.withLock { () -> (TimeInterval, Float)? in
            guard let recorder, recorder.isRecording else { return nil }
            recorder.updateMeters()
            let power = recorder.peakPower(forChannel: 0)
            maximumPeakPowerDBFS = max(maximumPeakPowerDBFS, power)
            return (recorder.currentTime, power)
        }
        guard let sample else { return }
        continuation.yield(.elapsed(sample.0))
        continuation.yield(.peakPower(sample.1))
    }

    private func installAudioSessionNotifications() {
        #if os(iOS) || os(watchOS)
        let center = NotificationCenter.default
        notificationTokens.append(center.addObserver(forName: AVAudioSession.interruptionNotification,
            object: nil, queue: nil) { [weak self] notification in
            guard let raw = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  AVAudioSession.InterruptionType(rawValue: raw) == .began else { return }
            self?.continuation.yield(.interruption)
        })
        notificationTokens.append(center.addObserver(forName: AVAudioSession.routeChangeNotification,
            object: nil, queue: nil) { [weak self] _ in
            self?.continuation.yield(.routeChanged)
        })
        #endif
    }

    private func deactivateAudioSession() {
        #if os(iOS) || os(watchOS)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        #endif
    }
}
