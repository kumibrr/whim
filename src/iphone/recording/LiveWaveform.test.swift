import XCTest
import WhimIPhone

final class LiveWaveformTests: XCTestCase {
    func testTheDefaultWaveformIsTheLogoCurveSpanningTheFullWidth() {
        let curve = LiveWaveform.resting
        XCTAssertEqual(curve.start, WaveformPoint(x: 0, y: 0))
        XCTAssertEqual(curve.segments.last?.end, WaveformPoint(x: 1, y: 0))
        let heights = logoPoints().map(\.y)
        XCTAssertEqual(heights.max() ?? 0, 1, accuracy: 0.0001)
        XCTAssertLessThan(heights.min() ?? 0, -0.4)
        XCTAssertGreaterThan(curve.accent.y, 0.3)
    }

    func testTheLogoCurveEntersAndLeavesFlat() {
        let edges = logoPoints().filter { $0.x < 0.1 || $0.x > 0.9 }
        XCTAssertTrue(edges.allSatisfy { abs($0.y) < 0.0001 })
    }

    func testRecordingStaysFlatUntilSomebodySpeaks() {
        for power in [-160.0, -55, -48, -.infinity, .infinity, .nan] {
            let level = LiveWaveform.level(power: power)
            XCTAssertTrue(trace(level: level, tone: 0.6).allSatisfy { $0 == 0 })
        }
    }

    func testLevelSpansTheHumanVoiceRange() {
        XCTAssertEqual(LiveWaveform.level(power: -50), 0)
        XCTAssertGreaterThan(LiveWaveform.level(power: -30), 0.3)
        XCTAssertLessThan(LiveWaveform.level(power: -30), 0.7)
        XCTAssertEqual(LiveWaveform.level(power: -6), 1)
        XCTAssertEqual(LiveWaveform.level(power: 0), 1)
    }

    func testASpeakingVoiceDrawsAWaveformRatherThanTheLogo() {
        let speaking = trace(level: 1, tone: 0.5)
        let crossings = zip(speaking, speaking.dropFirst()).filter { $0 * $1 < 0 }.count
        XCTAssertGreaterThanOrEqual(crossings, 5)
        let peak = speaking.max() ?? 0
        let dip = speaking.min() ?? 0
        XCTAssertEqual(peak, -dip, accuracy: 0.15)
        let logo = logoPoints().map(\.y)
        XCTAssertGreaterThan(abs((logo.max() ?? 0) + (logo.min() ?? 0)), 0.4)
    }

    func testVolumeOnlyScalesAmplitudeForTheSameTone() {
        for x in [0.2, 0.35, 0.5, 0.65, 0.8] {
            let soft = LiveWaveform.displacement(at: x, level: 0.3, tone: 0.4)
            let loud = LiveWaveform.displacement(at: x, level: 0.6, tone: 0.4)
            XCTAssertEqual(loud, soft * 2, accuracy: 0.000001)
        }
    }

    func testVoiceToneReshapesTheTraceAtTheSameVolume() {
        let dark = trace(level: 0.6, tone: 0.2)
        let bright = trace(level: 0.6, tone: 0.8)
        XCTAssertTrue(zip(dark, bright).contains { $0 * $1 < -0.0001 })
        XCTAssertGreaterThan(cycles(of: bright), cycles(of: dark))
    }

    func testTheTraceTapersAtBothEdges() {
        for tone in [0.0, 0.3, 0.6, 1] {
            for x in [0.0, 0.02, 0.98, 1] {
                XCTAssertLessThan(abs(LiveWaveform.displacement(at: x, level: 1, tone: tone)), 0.01)
            }
        }
    }

    func testTheTraceStaysInsideItsFrameForEveryInput() {
        for tone in [0.0, 0.5, 1, .nan] {
            for level in [0.0, 0.5, 1, .nan] {
                XCTAssertTrue(trace(level: level, tone: tone).allSatisfy { $0.isFinite && abs($0) <= 1 })
            }
        }
    }

    private func cycles(of samples: [Double]) -> Int {
        zip(samples, samples.dropFirst()).filter { $0 * $1 < 0 }.count
    }

    private func trace(level: Double, tone: Double) -> [Double] {
        (0...240).map { LiveWaveform.displacement(at: Double($0) / 240, level: level, tone: tone) }
    }

    private func logoPoints() -> [WaveformPoint] {
        let curve = LiveWaveform.resting
        return [curve.start] + curve.segments.flatMap { [$0.control1, $0.control2, $0.end] }
    }
}
