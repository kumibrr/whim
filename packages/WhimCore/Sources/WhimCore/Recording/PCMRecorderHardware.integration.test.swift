import AVFoundation
import XCTest
@testable import WhimCore

final class PCMRecorderHardwareIntegrationTests: XCTestCase {
    #if DEBUG
    func testCaptureLatencyObservesStartedInputAndFirstEncodedBuffer() throws {
        let input = FixturePCMInput()
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".m4a")
        defer { try? FileManager.default.removeItem(at: url) }
        CaptureLatencyProbe.shared.begin()
        let hardware = PCMRecorderHardware(url: url, input: input)
        XCTAssertTrue(hardware.prepareToRecord())
        XCTAssertTrue(hardware.record())
        defer { hardware.stop() }
        input.send(try buffer(frequency: 800))
        let timing = CaptureLatencyProbe.shared.snapshot()
        let started = try XCTUnwrap(timing[.audioEngineStarted])
        let encoded = try XCTUnwrap(timing[.firstEncodedBuffer])
        XCTAssertLessThanOrEqual(started, encoded)
    }
    #endif

    func testCapturedPCMChangesToneWithoutDependingOnVolume() throws {
        let input = FixturePCMInput()
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".m4a")
        defer { try? FileManager.default.removeItem(at: url) }
        let hardware = PCMRecorderHardware(url: url, input: input)
        XCTAssertTrue(hardware.prepareToRecord())
        XCTAssertTrue(hardware.record())
        defer { hardware.stop() }
        input.send(try buffer(frequency: 200))
        let low = try XCTUnwrap(hardware.signal)
        input.send(try buffer(frequency: 1600))
        let high = try XCTUnwrap(hardware.signal)
        XCTAssertEqual(low.peakPowerDBFS, high.peakPowerDBFS, accuracy: 0.5)
        XCTAssertGreaterThan(high.tone - low.tone, 0.4)
    }

    func testAdapterPublishesMeasuredToneAndFinalizesPlayableMonoAAC() async throws {
        let input = FixturePCMInput()
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".m4a")
        defer { try? FileManager.default.removeItem(at: url) }
        let adapter = AVAudioRecorderAdapter(makeHardware: { PCMRecorderHardware(url: $0, input: input) })
        let events = await adapter.events()
        try await adapter.start(at: url)
        for _ in 0..<10 { input.send(try buffer(frequency: 800)) }
        try await adapter.stop()
        var gotTone = false
        for await event in events {
            if case .failure = event { return XCTFail("Unexpected capture failure") }
            if case .signal(let value) = event { gotTone = value.tone > 0.5 }
            if case .encoderCompleted(let duration, _) = event {
                XCTAssertEqual(duration, 1, accuracy: 0.02)
                break
            }
        }
        XCTAssertTrue(gotTone, "The recorder must publish tone from the actual saved input")
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        let audio = try AVAudioFile(forReading: url)
        XCTAssertEqual(audio.processingFormat.sampleRate, 16000)
        XCTAssertEqual(audio.processingFormat.channelCount, 1)
        XCTAssertEqual(audio.fileFormat.streamDescription.pointee.mFormatID, kAudioFormatMPEG4AAC)
        XCTAssertEqual(Double(audio.length) / audio.processingFormat.sampleRate, 1, accuracy: 0.05)
        let decoded = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: audio.processingFormat, frameCapacity: 16000))
        try audio.read(into: decoded)
        let samples = Array(UnsafeBufferPointer(start: try XCTUnwrap(decoded.floatChannelData)[0], count: Int(decoded.frameLength)))
        XCTAssertGreaterThan(RecordingSignal.measure(samples, sampleRate: 16000).peakPowerDBFS, -10)
    }

    func testFailedInputStartReleasesInputAndClosesTheWriter() throws {
        let input = FixturePCMInput()
        input.failStart = true
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".m4a")
        defer { try? FileManager.default.removeItem(at: url) }
        let hardware = PCMRecorderHardware(url: url, input: input)
        XCTAssertTrue(hardware.prepareToRecord())
        XCTAssertFalse(hardware.record())
        XCTAssertFalse(hardware.isRecording)
        XCTAssertTrue(input.stopped)
    }

    func testInputInterruptionUsesRecoverableInterruptionPath() async throws {
        let input = FixturePCMInput()
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".m4a")
        defer { try? FileManager.default.removeItem(at: url) }
        let adapter = AVAudioRecorderAdapter(makeHardware: { PCMRecorderHardware(url: $0, input: input) })
        let events = await adapter.events()
        try await adapter.start(at: url)
        input.interrupt()
        var iterator = events.makeAsyncIterator()
        let event = await iterator.next()
        XCTAssertEqual(event, .interruption)
        await adapter.discard()
    }

    func testBriefSpeechBeforeSilenceStillCountsAsMeaningfulCapture() async throws {
        let input = FixturePCMInput()
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".m4a")
        defer { try? FileManager.default.removeItem(at: url) }
        let adapter = AVAudioRecorderAdapter(makeHardware: { PCMRecorderHardware(url: $0, input: input) })
        let events = await adapter.events()
        try await adapter.start(at: url)
        input.send(try buffer(frequency: 800))
        input.send(try buffer(frequency: 0))
        input.send(try buffer(frequency: 0))
        try await adapter.stop()
        for await event in events {
            if case .failure = event { return XCTFail("Unexpected capture failure") }
            if case .encoderCompleted(_, let peak) = event {
                XCTAssertGreaterThan(peak, -10, "Quiet ending must not erase the earlier speech peak")
                break
            }
        }
    }

    private func buffer(frequency: Double, sampleRate: Double = 48000) throws -> AVAudioPCMBuffer {
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1))
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(sampleRate / 10)))
        buffer.frameLength = buffer.frameCapacity
        let samples = try XCTUnwrap(buffer.floatChannelData)[0]
        for i in 0..<Int(buffer.frameLength) { samples[i] = Float(0.5 * sin(2 * .pi * frequency * Double(i) / sampleRate)) }
        return buffer
    }
}

private final class FixturePCMInput: PCMInput, @unchecked Sendable {
    var failStart = false
    var stopped = false
    private var interruption: (@Sendable () -> Void)?
    private var receive: (@Sendable (AVAudioPCMBuffer) -> Void)?
    func start(receive: @escaping @Sendable (AVAudioPCMBuffer) -> Void, interruption: @escaping @Sendable () -> Void) throws { self.receive = receive; self.interruption = interruption; if failStart { throw AVAudioRecorderAdapterError.couldNotStart } }
    func stop() { stopped = true; receive = nil }
    func interrupt() { interruption?() }
    func send(_ buffer: AVAudioPCMBuffer) { receive?(buffer) }
}
