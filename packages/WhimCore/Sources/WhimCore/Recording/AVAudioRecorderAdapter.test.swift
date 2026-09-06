import Foundation
import XCTest
@testable import WhimCore

final class AVAudioRecorderAdapterTests: XCTestCase {
    // Break: Stop cancels metering before sampling sound captured after the last timer tick.
    func testStopSamplesFinalPeakBeforeClosingEncoder() async throws {
        let hardware = AudioRecorderHardwareFake(elapsed: 0.05, peakPowerDBFS: -12)
        let adapter = AVAudioRecorderAdapter(makeHardware: { _ in hardware })
        let events = await adapter.events()
        try await adapter.start(at: URL(fileURLWithPath: "/tmp/final-sample.m4a"))

        try await adapter.stop()

        let updateMeterCount = hardware.updateMeterCount
        XCTAssertEqual(updateMeterCount, 1)
        guard updateMeterCount == 1 else { return }
        var iterator = events.makeAsyncIterator()
        var received: [RecordingEvent] = []
        for _ in 0..<3 { if let event = await iterator.next() { received.append(event) } }
        XCTAssertEqual(received, [
            .elapsed(0.05),
            .peakPower(-12),
            .encoderCompleted(duration: 0.05, peakPowerDBFS: -12),
        ])
    }

    // Break: A delayed delegate callback from a discarded recorder clears a newer capture.
    func testDiscardedHardwareCompletionCannotCorruptNewCapture() async throws {
        let oldHardware = AudioRecorderHardwareFake(
            elapsed: 1,
            peakPowerDBFS: -20,
            completesWhenStopped: false
        )
        let newHardware = AudioRecorderHardwareFake(elapsed: 2, peakPowerDBFS: -8)
        let factory = AudioRecorderHardwareFactoryFake([oldHardware, newHardware])
        let adapter = AVAudioRecorderAdapter(makeHardware: { _ in factory.make() })
        let events = await adapter.events()

        try await adapter.start(at: URL(fileURLWithPath: "/tmp/old.m4a"))
        await adapter.discard()
        try await adapter.start(at: URL(fileURLWithPath: "/tmp/new.m4a"))

        oldHardware.finish(successfully: true)
        try await adapter.stop()

        var iterator = events.makeAsyncIterator()
        var received: [RecordingEvent] = []
        for _ in 0..<3 { if let event = await iterator.next() { received.append(event) } }
        XCTAssertEqual(received, [
            .elapsed(2),
            .peakPower(-8),
            .encoderCompleted(duration: 2, peakPowerDBFS: -8),
        ])
    }
}

private final class AudioRecorderHardwareFake: AudioRecorderHardware, @unchecked Sendable {
    let elapsedTime: TimeInterval
    let peakPowerDBFS: Float
    var isRecording = false
    private(set) var updateMeterCount = 0
    private var eventHandler: (@Sendable (AudioRecorderHardwareEvent) -> Void)?
    private let completesWhenStopped: Bool

    init(elapsed: TimeInterval, peakPowerDBFS: Float, completesWhenStopped: Bool = true) {
        elapsedTime = elapsed
        self.peakPowerDBFS = peakPowerDBFS
        self.completesWhenStopped = completesWhenStopped
    }

    func setEventHandler(_ handler: @escaping @Sendable (AudioRecorderHardwareEvent) -> Void) {
        eventHandler = handler
    }
    func prepareToRecord() -> Bool { true }
    func record() -> Bool { isRecording = true; return true }
    func updateMeters() { updateMeterCount += 1 }
    func stop() {
        isRecording = false
        if completesWhenStopped { finish(successfully: true) }
    }
    func deleteRecording() -> Bool { true }
    func finish(successfully: Bool) { eventHandler?(.finished(successfully: successfully)) }
}

private final class AudioRecorderHardwareFactoryFake: @unchecked Sendable {
    private let lock = NSLock()
    private var hardware: [AudioRecorderHardwareFake]

    init(_ hardware: [AudioRecorderHardwareFake]) { self.hardware = hardware }

    func make() -> AudioRecorderHardwareFake {
        lock.withLock { hardware.removeFirst() }
    }
}
