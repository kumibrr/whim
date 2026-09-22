#if DEBUG
import Foundation

/// Local, bounded development diagnostics. Never logged, persisted, or compiled into Release.
public final class CaptureLatencyProbe: @unchecked Sendable {
    public enum Stage: String, Sendable { case invocationReceived, sessionPersisted, audioEngineStarted, firstEncodedBuffer }
    public static let shared = CaptureLatencyProbe()
    private let lock = NSLock()
    private var timestamps: [Stage: UInt64] = [:]
    public init() {}
    public func begin() { lock.withLock { timestamps = [.invocationReceived: DispatchTime.now().uptimeNanoseconds] } }
    public func mark(_ stage: Stage) { lock.withLock { if timestamps[stage] == nil { timestamps[stage] = DispatchTime.now().uptimeNanoseconds } } }
    public func snapshot() -> [Stage: UInt64] { lock.withLock { timestamps } }
}
#endif
