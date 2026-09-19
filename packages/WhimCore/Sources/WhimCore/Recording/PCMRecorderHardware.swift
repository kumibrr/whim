import AVFoundation
import Foundation

/// Raw microphone boundary. The receiver consumes the buffer before returning.
protocol PCMInput: AnyObject, Sendable {
    func start(receive: @escaping @Sendable (AVAudioPCMBuffer) -> Void,
               interruption: @escaping @Sendable () -> Void) throws
    func stop()
}

final class PCMRecorderHardware: AudioRecorderHardware, @unchecked Sendable {
    private let input: any PCMInput
    private let url: URL
    private let lock = NSLock()
    private var file: AVAudioFile?
    private var converter: AVAudioConverter?
    private let outputFormat = AVAudioFormat(standardFormatWithSampleRate: 16000, channels: 1)!
    private var failed = false
    private var active = false
    private var latestSignal: RecordingSignal?
    private var capturedPeak: Float = -160
    private var duration: TimeInterval = 0
    private var handler: (@Sendable (AudioRecorderHardwareEvent) -> Void)?
    init(url: URL, input: any PCMInput) { self.url = url; self.input = input }
    var isRecording: Bool { lock.withLock { active } }
    var elapsedTime: TimeInterval { lock.withLock { duration } }
    var peakPowerDBFS: Float { lock.withLock { capturedPeak } }
    var signal: RecordingSignal? { lock.withLock { latestSignal } }
    func setEventHandler(_ handler: @escaping @Sendable (AudioRecorderHardwareEvent) -> Void) {
        lock.withLock { self.handler = handler }
    }
    func prepareToRecord() -> Bool {
        lock.withLock {
            do { file = try AVAudioFile(forWriting: url, settings: RecordingEncoding.settings); return true }
            catch { return false }
        }
    }
    func record() -> Bool {
        lock.withLock { active = true }
        do {
            try input.start(receive: { [weak self] in self?.receive($0) }, interruption: { [weak self] in self?.interrupted() })
            return true
        } catch {
            lock.withLock { active = false; file = nil; converter = nil }
            input.stop()
            return false
        }
    }
    private func receive(_ buffer: AVAudioPCMBuffer) {
        let error = lock.withLock { () -> Bool in
            guard active, !failed, buffer.frameLength > 0 else { return false }
            do {
                try convert(buffer)
                duration += Double(buffer.frameLength) / buffer.format.sampleRate
                return false
            } catch { return true }
        }
        if error { fail() }
    }

    // Called under lock: encoding and analysis consume the same converted mono PCM.
    private func convert(_ input: AVAudioPCMBuffer?) throws {
        if converter == nil, let input {
            converter = AVAudioConverter(from: input.format, to: outputFormat)
            converter?.primeMethod = .none
            converter?.downmix = true
        }
        guard let converter, let file else {
            if input == nil { return }
            throw AVAudioRecorderAdapterError.couldNotStart
        }
        if let input, input.format != converter.inputFormat { throw AVAudioRecorderAdapterError.couldNotStart }
        let capacity = input.map { Int(ceil(Double($0.frameLength) * 16000 / $0.format.sampleRate)) + 128 } ?? 4096
        guard let output = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: AVAudioFrameCount(capacity)) else {
            throw AVAudioRecorderAdapterError.couldNotStart
        }
        var supplied = false
        while true {
            var error: NSError?
            let status = converter.convert(to: output, error: &error) { _, status in
                guard let input else { status.pointee = .endOfStream; return nil }
                guard !supplied else { status.pointee = .noDataNow; return nil }
                supplied = true
                status.pointee = .haveData
                return input
            }
            if let error { throw error }
            if status == .error { throw AVAudioRecorderAdapterError.couldNotStart }
            if output.frameLength > 0 {
                try file.write(from: output)
                if input != nil, let channel = output.floatChannelData?[0] {
                    latestSignal = RecordingSignal.measure(Array(UnsafeBufferPointer(start: channel, count: Int(output.frameLength))),
                                                           sampleRate: 16000)
                    capturedPeak = max(capturedPeak, latestSignal?.peakPowerDBFS ?? -160)
                }
            }
            if status != .haveData || output.frameLength == 0 { return }
        }
    }

    private func interrupted() {
        let callback = lock.withLock { active ? handler : nil }
        callback?(.interrupted)
    }

    private func fail() {
        let callback = lock.withLock { () -> (@Sendable (AudioRecorderHardwareEvent) -> Void)? in
            guard active, !failed else { return nil }
            failed = true
            return handler
        }
        callback?(.failed)
    }
    func updateMeters() {}
    func stop() {
        let wasActive = lock.withLock { let value = active; active = false; return value }
        input.stop()
        let success = lock.withLock { () -> Bool in
            defer { file = nil; converter = nil }
            do { try convert(nil); return !failed }
            catch { return false }
        }
        if wasActive { lock.withLock { handler }?(.finished(successfully: success)) }
    }
    func deleteRecording() -> Bool { (try? FileManager.default.removeItem(at: url)) != nil }
}

#if os(iOS)
/// A single microphone tap supplies both the AAC writer and the signal measurements.
final class SystemPCMInput: PCMInput, @unchecked Sendable {
    private let engine = AVAudioEngine()
    private let lock = NSLock()
    private var active = false
    private var tapInstalled = false
    private var observer: NSObjectProtocol?

    func start(receive: @escaping @Sendable (AVAudioPCMBuffer) -> Void,
               interruption: @escaping @Sendable () -> Void) throws {
        let node = engine.inputNode
        let format = node.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            throw AVAudioRecorderAdapterError.couldNotStart
        }
        node.installTap(onBus: 0, bufferSize: 2048, format: format) { buffer, _ in receive(buffer) }
        tapInstalled = true
        observer = NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange,
            object: engine, queue: nil) { [weak self] _ in
                guard let self, self.lock.withLock({ self.active }) else { return }
                // A route-driven engine reconfiguration ends capture through the
                // existing interruption/finalization path, preserving captured audio.
                interruption()
            }
        do {
            engine.prepare()
            try engine.start()
            lock.withLock { active = true }
        } catch { stop(); throw error }
    }

    func stop() {
        lock.withLock { active = false }
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
        if tapInstalled { engine.inputNode.removeTap(onBus: 0); tapInstalled = false }
        engine.stop()
    }
    deinit { stop() }
}
#endif
