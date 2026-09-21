import XCTest
import WhimIPhone

final class LiveWaveformTests: XCTestCase {
    func testTheDefaultWaveformIsTheLogoCurveSpanningTheFullWidth() {
        let curve = LiveWaveform.resting
        XCTAssertEqual(curve.start, WaveformPoint(x: 0, y: 0))
        XCTAssertEqual(curve.segments.last?.end, WaveformPoint(x: 1, y: 0))
        let heights = points(curve).map(\.y)
        XCTAssertEqual(heights.max() ?? 0, 1, accuracy: 0.0001)
        XCTAssertLessThan(heights.min() ?? 0, -0.4)
        XCTAssertGreaterThan(curve.accent.y, 0.3)
    }

    func testTheCurveEntersAndLeavesFlat() {
        for tone in [0.0, 0.5, 1] {
            let edges = points(LiveWaveform.curve(level: 1, tone: tone)).filter { $0.x < 0.1 || $0.x > 0.9 }
            XCTAssertTrue(edges.allSatisfy { abs($0.y) < 0.0001 })
        }
    }

    func testRecordingStaysFlatUntilSomebodySpeaks() {
        for power in [-160.0, -55, -48, -.infinity, .infinity, .nan] {
            let curve = LiveWaveform.curve(level: LiveWaveform.level(power: power), tone: 0.6)
            XCTAssertTrue(points(curve).allSatisfy { $0.y == 0 })
            XCTAssertEqual(curve.accent.y, 0)
        }
    }

    func testLevelSpansTheHumanVoiceRange() {
        XCTAssertEqual(LiveWaveform.level(power: -50), 0)
        XCTAssertGreaterThan(LiveWaveform.level(power: -30), 0.3)
        XCTAssertLessThan(LiveWaveform.level(power: -30), 0.7)
        XCTAssertEqual(LiveWaveform.level(power: -6), 1)
        XCTAssertEqual(LiveWaveform.level(power: 0), 1)
    }

    func testVolumeOnlyScalesAmplitudeForTheSameTone() {
        let soft = points(LiveWaveform.curve(level: 0.3, tone: 0.4))
        let loud = points(LiveWaveform.curve(level: 0.6, tone: 0.4))
        for (quiet, strong) in zip(soft, loud) {
            XCTAssertEqual(strong.x, quiet.x, accuracy: 0.000001)
            XCTAssertEqual(strong.y, quiet.y * 2, accuracy: 0.000001)
        }
        XCTAssertEqual(LiveWaveform.curve(level: 0.5, tone: 0).accent.y,
                       LiveWaveform.resting.accent.y / 2, accuracy: 0.000001)
    }

    func testBrighterVoicesTightenTheCurveWithoutChangingItsHeights() {
        let dark = points(LiveWaveform.curve(level: 0.6, tone: 0.2))
        let bright = points(LiveWaveform.curve(level: 0.6, tone: 0.8))
        XCTAssertEqual(dark.map(\.y), bright.map(\.y))
        XCTAssertLessThan(voiceWidth(tone: 1), voiceWidth(tone: 0) * 0.85)
    }

    func testTheCurveStaysInsideItsFrameForEveryInput() {
        for tone in [0.0, 0.5, 1, .nan] {
            for level in [0.0, 0.5, 1, .nan] {
                for point in points(LiveWaveform.curve(level: level, tone: tone)) {
                    XCTAssertTrue((0...1).contains(point.x))
                    XCTAssertLessThanOrEqual(abs(point.y), 1)
                }
            }
        }
    }

    private func voiceWidth(tone: Double) -> Double {
        let active = points(LiveWaveform.curve(level: 1, tone: tone)).filter { abs($0.y) > 0.001 }
        return (active.map(\.x).max() ?? 0) - (active.map(\.x).min() ?? 0)
    }

    private func points(_ curve: WaveformCurve) -> [WaveformPoint] {
        [curve.start] + curve.segments.flatMap { [$0.control1, $0.control2, $0.end] }
    }
}
