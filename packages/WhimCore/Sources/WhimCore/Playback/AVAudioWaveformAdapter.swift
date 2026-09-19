import AVFoundation
import Foundation

/// Decodes bounded PCM chunks on its own actor, independently of capture commands.
public actor AVAudioWaveformAdapter: AudioWaveformAdapter {
    private struct Entry {
        let modified: Date?
        let size: Int
        let samples: [Float]
    }
    private var cache: [URL: Entry] = [:]
    private var order: [URL] = []
    public init() {}

    public func waveform(at url: URL) throws -> [Float] {
        try Task.checkCancellation()
        let values = try url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
        if let entry = cache[url], entry.modified == values.contentModificationDate,
           entry.size == values.fileSize { return entry.samples }
        let file = try AVAudioFile(forReading: url, commonFormat: .pcmFormatFloat32, interleaved: false)
        guard file.length > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 4096) else {
            throw WhimServiceError.audioUnavailable
        }
        var samples = [Float](repeating: 0, count: 64)
        var offset: AVAudioFramePosition = 0
        while offset < file.length {
            try Task.checkCancellation()
            try file.read(into: buffer, frameCount: AVAudioFrameCount(min(4096, file.length - offset)))
            guard buffer.frameLength > 0, let channels = buffer.floatChannelData else {
                throw WhimServiceError.audioUnavailable
            }
            for frame in 0..<Int(buffer.frameLength) {
                let bin = min(63, Int((offset + Int64(frame)) * 64 / file.length))
                for channel in 0..<Int(buffer.format.channelCount) {
                    let value = abs(channels[channel][frame])
                    if value.isFinite { samples[bin] = max(samples[bin], min(1, value)) }
                }
            }
            offset += Int64(buffer.frameLength)
        }
        try Task.checkCancellation()
        order.removeAll { $0 == url }
        order.append(url)
        cache[url] = Entry(modified: values.contentModificationDate, size: values.fileSize ?? 0, samples: samples)
        while order.count > 64 { cache.removeValue(forKey: order.removeFirst()) }
        return samples
    }
}
