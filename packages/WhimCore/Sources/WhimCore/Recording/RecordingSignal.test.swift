import XCTest
@testable import WhimCore

final class RecordingSignalTests: XCTestCase {
    func testToneSpreadsHumanVoiceFrequenciesAcrossItsRange() {
        let low = signal(frequency: 150)
        let high = signal(frequency: 1200)
        XCTAssertEqual(low.peakPowerDBFS, high.peakPowerDBFS, accuracy: 0.5)
        XCTAssertLessThan(low.tone, 0.3)
        XCTAssertGreaterThan(high.tone, 0.7)
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

    func testRumbleBelowTheVoiceBandDoesNotFlattenTone() {
        let voice = signal(frequency: 300, amplitude: 0.25)
        let overRumble = signal(frequencies: [300, 45], amplitude: 0.25)
        XCTAssertEqual(overRumble.tone, voice.tone, accuracy: 0.05)
    }

    func testHissAboveTheVoiceBandDoesNotBrightenTone() {
        let voice = signal(frequency: 300, amplitude: 0.25)
        let overHiss = signal(frequencies: [300, 7000], amplitude: 0.25)
        XCTAssertEqual(overHiss.tone, voice.tone, accuracy: 0.15)
    }

    func testSoundQuieterThanASpeakingVoiceReportsNoTone() {
        let distant = signal(frequency: 300, amplitude: 0.002)
        XCTAssertLessThan(distant.peakPowerDBFS, -50)
        XCTAssertEqual(distant.tone, 0)
        XCTAssertGreaterThan(signal(frequency: 300, amplitude: 0.05).tone, 0)
    }

    func testSilenceAndInvalidSamplesDoNotCreateActivity() {
        for samples: [Float] in [[], [0, 0, 0], [.nan, .infinity]] {
            let value = RecordingSignal.measure(samples, sampleRate: 16000)
            XCTAssertEqual(value.peakPowerDBFS, -160)
            XCTAssertEqual(value.tone, 0)
        }
    }

    private func signal(frequency: Double, amplitude: Float = 0.5, phase: Double = 0) -> RecordingSignal {
        signal(frequencies: [frequency], amplitude: amplitude, phase: phase)
    }

    private func signal(frequencies: [Double], amplitude: Float = 0.5, phase: Double = 0) -> RecordingSignal {
        let samples = (0..<1600).map { index in
            frequencies.reduce(Float(0)) { total, frequency in
                total + amplitude * Float(sin(2 * .pi * frequency * Double(index) / 16000 + phase))
            }
        }
        return RecordingSignal.measure(samples, sampleRate: 16000)
    }
}
