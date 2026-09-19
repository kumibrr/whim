import Foundation

public enum AudioWaveform: Equatable, Sendable {
    case samples([Float])
    case unavailable
}

public protocol AudioWaveformAdapter: Sendable {
    func waveform(at url: URL) async throws -> [Float]
}
