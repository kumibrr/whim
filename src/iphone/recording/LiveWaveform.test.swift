import XCTest
import WhimIPhone

final class LiveWaveformTests: XCTestCase {
    func testToneReshapesTheCurveAtTheSameVolume() {
        let low = (0...240).map { LiveWaveform.displacement(at: Double($0) / 240, level: 0.6, tone: 0.2) }
        let high = (0...240).map { LiveWaveform.displacement(at: Double($0) / 240, level: 0.6, tone: 0.8) }
        XCTAssertTrue(zip(low, high).contains { $0 * $1 < -0.0001 })
    }

    func testVolumeOnlyChangesAmplitudeForTheSameTone() {
        for x in [0.2, 0.35, 0.5, 0.65, 0.8] {
            let soft = LiveWaveform.displacement(at: x, level: 0.3, tone: 0.4)
            let loud = LiveWaveform.displacement(at: x, level: 0.6, tone: 0.4)
            XCTAssertEqual(loud, soft * 2, accuracy: 0.000001)
        }
    }

    func testSilenceAndInvalidMeterValuesRemainFlat() {
        for power in [-160.0, -60, -.infinity, .infinity, .nan] {
            XCTAssertTrue(samples(power: power, tone: 0.6).allSatisfy { $0 == 0 })
        }
    }

    func testCurveRemainsBoundedAcrossTheScreen() {
        for tone in [0.0, 0.3, 0.6, 1] {
            let values = samples(power: 0, tone: tone)
            XCTAssertTrue(values.allSatisfy { $0.isFinite && abs($0) <= 0.46 })
        }
    }

    func testEdgesStayAlmostFlatAcrossToneChanges() {
        for tone in [0.0, 0.3, 0.6, 1] {
            for x in [0.0, 0.02, 0.98, 1] {
                XCTAssertLessThan(abs(LiveWaveform.displacement(at: x, level: 1, tone: tone)), 0.003)
            }
        }
    }

    private func samples(power: Double, tone: Double) -> [Double] {
        (0...240).map { LiveWaveform.displacement(at: Double($0) / 240,
            level: LiveWaveform.level(power: power), tone: tone) }
    }
}
