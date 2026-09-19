import AVFoundation
import XCTest
@testable import WhimCore

final class AVAudioWaveformAdapterIntegrationTests: XCTestCase {
    func testWaveformPreservesSilenceAndPositionOfSound() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("caf")
        defer { try? FileManager.default.removeItem(at: url) }
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 16000, channels: 1))
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 16000))
        buffer.frameLength = 16000
        let samples = try XCTUnwrap(buffer.floatChannelData)[0]
        for frame in 0..<16000 { samples[frame] = frame < 8000 ? 0.5 : 0 }
        do { let file = try AVAudioFile(forWriting: url, settings: format.settings); try file.write(from: buffer) }
        let adapter = AVAudioWaveformAdapter()
        let result = try await adapter.waveform(at: url)
        XCTAssertEqual(result.count, 64)
        XCTAssertTrue(result.prefix(32).allSatisfy { abs($0 - 0.5) < 0.001 })
        XCTAssertTrue(result.suffix(32).allSatisfy { $0 == 0 })
        for frame in 0..<16000 { samples[frame] = 0 }
        try FileManager.default.removeItem(at: url)
        do { let file = try AVAudioFile(forWriting: url, settings: format.settings); try file.write(from: buffer) }
        let silence = try await AVAudioWaveformAdapter().waveform(at: url)
        XCTAssertEqual(silence, Array(repeating: 0, count: 64))
    }
    func testCorruptAudioCannotBecomeDecorativeSamples() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        try Data("not audio".utf8).write(to: url)
        do {
            _ = try await AVAudioWaveformAdapter().waveform(at: url)
            XCTFail("Corrupt audio must fail decoding")
        } catch {}
    }
}
