import AVFoundation
import Foundation
import XCTest
@testable import WhimCore

final class AVAudioRecorderSessionIntegrationTests: XCTestCase {
    // Break: The requested bitrate cannot be encoded at the recorder's sample rate/channel count.
    // Exercise Apple's real AAC encoder without depending on microphone permission or input.
    func testRecordingEncodingProducesPlayableMonoAudio() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("encoding.m4a")
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1))
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 16_000))
        buffer.frameLength = buffer.frameCapacity
        let samples = try XCTUnwrap(buffer.floatChannelData)[0]
        for frame in 0..<Int(buffer.frameLength) {
            samples[frame] = 0.1 * sin(Float(frame) * 2 * .pi * 440 / 16_000)
        }
        // Closing the writer finalizes the container before checking it through the read boundary.
        do {
            let writer = try AVAudioFile(forWriting: url, settings: RecordingEncoding.settings)
            try writer.write(from: buffer)
        }
        let audio = try AVAudioFile(forReading: url)
        XCTAssertEqual(audio.fileFormat.streamDescription.pointee.mFormatID, kAudioFormatMPEG4AAC)
        XCTAssertEqual(audio.processingFormat.channelCount, 1)
        XCTAssertEqual(Double(audio.length) / audio.processingFormat.sampleRate, 1, accuracy: 0.1)
        let decoded = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: audio.processingFormat, frameCapacity: 16_000))
        try audio.read(into: decoded)
        XCTAssertGreaterThan(decoded.frameLength, 0)
        let decodedSamples = try XCTUnwrap(decoded.floatChannelData)[0]
        XCTAssertTrue((0..<Int(decoded.frameLength)).contains { abs(decodedSamples[$0]) > 0.01 })
    }

    #if os(iOS)
    // Break: A playback-only mode reaches the iPhone recording session and fails with -50.
    // The simulator accepts spokenAudio, so also check the policy applied to the real session.
    func testIPhoneCaptureUsesARecordingCompatibleSessionMode() async throws {
        let hardware = SessionTestRecorderHardware()
        let adapter = AVAudioRecorderAdapter(makeHardware: { _ in hardware })

        try await adapter.start(at: URL(fileURLWithPath: "/tmp/session-mode.m4a"))

        let session = AVAudioSession.sharedInstance()
        XCTAssertEqual(session.category, .record)
        XCTAssertTrue([AVAudioSession.Mode.default, .measurement].contains(session.mode),
                      "Capture must use a recording mode, got \(session.mode.rawValue)")
        XCTAssertTrue(hardware.isRecording)
        await adapter.discard()
    }
    #endif

}

#if os(iOS)
private final class SessionTestRecorderHardware: AudioRecorderHardware, @unchecked Sendable {
    var isRecording = false
    var elapsedTime: TimeInterval { 2 }
    var peakPowerDBFS: Float { -12 }
    func setEventHandler(_ handler: @escaping @Sendable (AudioRecorderHardwareEvent) -> Void) {}
    func prepareToRecord() -> Bool { true }
    func record() -> Bool { isRecording = true; return true }
    func updateMeters() {}
    func stop() { isRecording = false }
    func deleteRecording() -> Bool { true }
}
#endif
