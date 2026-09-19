import XCTest
@testable import WhimCore

final class RecordingSignalTests: XCTestCase {
    func testToneChangesAtTheSameVolume() {
        let low = signal(frequency: 200)
        let high = signal(frequency: 1600)
        XCTAssertEqual(low.peakPowerDBFS, high.peakPowerDBFS, accuracy: 0.5)
        XCTAssertGreaterThan(high.tone - low.tone, 0.4)
    }

    func testVolumeDoesNotChangeTone() {
        let soft = signal(frequency: 400, amplitude: 0.1)
        let loud = signal(frequency: 400, amplitude: 0.5)
        XCTAssertEqual(soft.tone, loud.tone, accuracy: 0.01)
        XCTAssertGreaterThan(loud.peakPowerDBFS - soft.peakPowerDBFS, 13)
    }

    func testSteadyToneIsStableAcrossInputBufferPhases() {
        XCTAssertEqual(signal(frequency: 220, phase: 0).tone,
                       signal(frequency: 220, phase: 1.4).tone, accuracy: 0.01)
    }

    func testSilenceAndInvalidSamplesDoNotCreateActivity() {
        for samples: [Float] in [[], [0, 0, 0], [.nan, .infinity]] {
            let value = RecordingSignal.measure(samples, sampleRate: 16000)
            XCTAssertEqual(value.peakPowerDBFS, -160)
            XCTAssertEqual(value.tone, 0)
        }
    }

    private func signal(frequency: Double, amplitude: Float = 0.5, phase: Double = 0) -> RecordingSignal {
        let samples = (0..<1600).map { amplitude * Float(sin(2 * .pi * frequency * Double($0) / 16000 + phase)) }
        return RecordingSignal.measure(samples, sampleRate: 16000)
    }
}
