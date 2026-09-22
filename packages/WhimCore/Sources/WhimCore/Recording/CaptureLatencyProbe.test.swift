#if DEBUG
import XCTest
@testable import WhimCore

final class CaptureLatencyProbeTests: XCTestCase {
    func testFirstObservationIsMonotonicAndNextSessionResetsIt() throws {
        let probe = CaptureLatencyProbe()
        probe.begin()
        probe.mark(.sessionPersisted)
        probe.mark(.audioEngineStarted)
        probe.mark(.firstEncodedBuffer)
        let first = probe.snapshot()
        probe.mark(.firstEncodedBuffer)
        XCTAssertEqual(first, probe.snapshot(), "Repeated audio buffers must not overwrite first-buffer latency")
        let invocation = try XCTUnwrap(first[.invocationReceived])
        let persisted = try XCTUnwrap(first[.sessionPersisted])
        let engine = try XCTUnwrap(first[.audioEngineStarted])
        let encoded = try XCTUnwrap(first[.firstEncodedBuffer])
        XCTAssertLessThanOrEqual(invocation, persisted)
        XCTAssertLessThanOrEqual(persisted, engine)
        XCTAssertLessThanOrEqual(engine, encoded)
        probe.begin()
        XCTAssertEqual(probe.snapshot().count, 1)
    }
}
#endif
