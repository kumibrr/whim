import AVFoundation
import Foundation

public enum AVAudioRecorderAdapterError: Error, Sendable {
    case couldNotStart
}

public enum AudioRecorderHardwareEvent: Sendable {
    case finished(successfully: Bool)
    case failed
}

/// Injectable system boundary around `AVAudioRecorder`. Tests supply deterministic hardware;
/// production uses the private AVFoundation implementation below.
public protocol AudioRecorderHardware: AnyObject, Sendable {
    var isRecording: Bool { get }
    var elapsedTime: TimeInterval { get }
    var peakPowerDBFS: Float { get }
    func setEventHandler(_ handler: @escaping @Sendable (AudioRecorderHardwareEvent) -> Void)
    func prepareToRecord() -> Bool
    func record() -> Bool
    func updateMeters()
    func stop()
    func deleteRecording() -> Bool
}

public typealias AudioRecorderHardwareFactory = @Sendable (URL) throws -> any AudioRecorderHardware

enum RecordingEncoding {
    static var settings: [String: Any] {
        [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 16_000,
            AVNumberOfChannelsKey: 1,
            // AAC at 16 kHz mono must use a bitrate supported by that format.
            AVEncoderBitRateKey: 32_000,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
        ]
    }
}

/// The platform microphone boundary. AVFoundation owns encoding and closes the AAC writer
/// before `encoderCompleted` is emitted.
public final class AVAudioRecorderAdapter: NSObject, AudioRecorder, @unchecked Sendable {
    private let lock = NSLock()
    private let operationLock = NSLock()
    private let makeHardware: AudioRecorderHardwareFactory
    private let eventStream: AsyncStream<RecordingEvent>
    private let continuation: AsyncStream<RecordingEvent>.Continuation
    private var hardware: (any AudioRecorderHardware)?
    private var generation: UUID?
    private var meterTask: Task<Void, Never>?
    private var maximumPeakPowerDBFS: Float = -160
    private var notificationTokens: [NSObjectProtocol] = []

    public override convenience init() {
        self.init(makeHardware: { try AVFoundationRecorderHardware(url: $0) })
    }

    public init(makeHardware: @escaping AudioRecorderHardwareFactory) {
        self.makeHardware = makeHardware
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
        try operationLock.withLock {
            #if os(watchOS)
            try WatchAudioSessionAdapter().activate()
            #elseif os(iOS)
            let session = AVAudioSession.sharedInstance()
            // spokenAudio is a playback mode; physical iPhones can reject it for capture.
            try session.setCategory(.record, mode: .default)
            try session.setActive(true)
            #endif

            do {
                guard lock.withLock({ hardware == nil }) else {
                    throw AVAudioRecorderAdapterError.couldNotStart
                }
                let hardware = try makeHardware(url)
                let generation = UUID()
                hardware.setEventHandler { [weak self] event in
                    self?.handle(event, generation: generation)
                }
                lock.withLock {
                    self.hardware = hardware
                    self.generation = generation
                    maximumPeakPowerDBFS = -160
                }
                guard hardware.prepareToRecord(), hardware.record() else {
                    clear(generation: generation)
                    throw AVAudioRecorderAdapterError.couldNotStart
                }
                beginMetering(generation: generation)
            } catch {
                deactivateAudioSession()
                throw error
            }
        }
    }

    public func stop() async throws {
        try operationLock.withLock {
            let current = lock.withLock { () -> ((any AudioRecorderHardware), UUID)? in
                guard let hardware, let generation else { return nil }
                return (hardware, generation)
            }
            guard let (hardware, generation) = current else {
                throw AVAudioRecorderAdapterError.couldNotStart
            }
            sampleMeters(generation: generation)
            cancelMetering(generation: generation)
            hardware.stop()
        }
    }

    public func discard() async {
        operationLock.withLock {
            let current = lock.withLock { () -> ((any AudioRecorderHardware)?, Task<Void, Never>?) in
                let current = (hardware, meterTask)
                hardware = nil
                generation = nil
                meterTask = nil
                maximumPeakPowerDBFS = -160
                return current
            }
            current.1?.cancel()
            current.0?.stop()
            _ = current.0?.deleteRecording()
            deactivateAudioSession()
        }
    }

    private func handle(_ event: AudioRecorderHardwareEvent, generation: UUID) {
        switch event {
        case .finished(let successfully):
            let terminal = lock.withLock { () -> (Task<Void, Never>?, TimeInterval, Float)? in
                guard self.generation == generation, let hardware else { return nil }
                let terminal = (meterTask, hardware.elapsedTime, maximumPeakPowerDBFS)
                meterTask = nil
                self.hardware = nil
                self.generation = nil
                return terminal
            }
            guard let (meterTask, duration, peak) = terminal else { return }
            meterTask?.cancel()
            deactivateAudioSession()
            if successfully {
                continuation.yield(.encoderCompleted(duration: duration, peakPowerDBFS: peak))
            } else {
                continuation.yield(.failure)
            }
        case .failed:
            let isCurrent = lock.withLock { self.generation == generation }
            guard isCurrent else { return }
            cancelMetering(generation: generation)
            continuation.yield(.failure)
        }
    }

    private func beginMetering(generation: UUID) {
        let task = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(100))
                guard !Task.isCancelled else { return }
                self?.sampleMeters(generation: generation)
            }
        }
        lock.withLock {
            meterTask?.cancel()
            meterTask = task
        }
    }

    private func cancelMetering(generation: UUID) {
        let task = lock.withLock { () -> Task<Void, Never>? in
            guard self.generation == generation else { return nil }
            let task = meterTask
            meterTask = nil
            return task
        }
        task?.cancel()
    }

    private func sampleMeters(generation: UUID) {
        let sample = lock.withLock { () -> (TimeInterval, Float)? in
            guard self.generation == generation, let hardware, hardware.isRecording else { return nil }
            hardware.updateMeters()
            let power = hardware.peakPowerDBFS
            maximumPeakPowerDBFS = max(maximumPeakPowerDBFS, power)
            return (hardware.elapsedTime, power)
        }
        guard let sample else { return }
        continuation.yield(.elapsed(sample.0))
        continuation.yield(.peakPower(sample.1))
    }

    private func clear(generation: UUID) {
        lock.withLock {
            guard self.generation == generation else { return }
            meterTask?.cancel()
            meterTask = nil
            hardware = nil
            self.generation = nil
            maximumPeakPowerDBFS = -160
        }
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
        #if os(watchOS)
        WatchAudioSessionAdapter().deactivate()
        #elseif os(iOS)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        #endif
    }
}

private final class AVFoundationRecorderHardware: NSObject, AVAudioRecorderDelegate, AudioRecorderHardware,
    @unchecked Sendable {
    private let recorder: AVAudioRecorder
    private let lock = NSLock()
    private var eventHandler: (@Sendable (AudioRecorderHardwareEvent) -> Void)?

    init(url: URL) throws {
        recorder = try AVAudioRecorder(url: url, settings: RecordingEncoding.settings)
        super.init()
        recorder.delegate = self
        recorder.isMeteringEnabled = true
    }

    var isRecording: Bool { recorder.isRecording }
    var elapsedTime: TimeInterval { recorder.currentTime }
    var peakPowerDBFS: Float { recorder.peakPower(forChannel: 0) }

    func setEventHandler(_ handler: @escaping @Sendable (AudioRecorderHardwareEvent) -> Void) {
        lock.withLock { eventHandler = handler }
    }
    func prepareToRecord() -> Bool { recorder.prepareToRecord() }
    func record() -> Bool { recorder.record() }
    func updateMeters() { recorder.updateMeters() }
    func stop() { recorder.stop() }
    func deleteRecording() -> Bool { recorder.deleteRecording() }

    func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        lock.withLock { eventHandler }?(.finished(successfully: flag))
    }

    func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: Error?) {
        lock.withLock { eventHandler }?(.failed)
    }
}
