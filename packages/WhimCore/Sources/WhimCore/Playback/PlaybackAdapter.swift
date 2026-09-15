import Foundation
import AVFoundation

public struct PlaybackProjection: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let noteID: String
    public let isPlaying: Bool
    public let elapsedSeconds: TimeInterval
    public let durationSeconds: TimeInterval
    public init(noteID: NoteID, isPlaying: Bool, elapsedSeconds: TimeInterval, durationSeconds: TimeInterval) {
        schemaVersion = WhimCoreVersion.schema; self.noteID = noteID.rawValue.uuidString.lowercased()
        self.isPlaying = isPlaying; self.elapsedSeconds = elapsedSeconds; self.durationSeconds = durationSeconds
    }
}
public protocol PlaybackAdapter: Sendable {
    func play(noteID: NoteID, url: URL) async throws -> PlaybackProjection
    func stop() async
    func snapshot() async -> PlaybackProjection?
}
protocol PlaybackHardware: AnyObject, Sendable {
    var isPlaying: Bool { get }
    var currentTime: TimeInterval { get }
    var duration: TimeInterval { get }
    func prepareToPlay() -> Bool
    func play() -> Bool
    func stop()
    func onCompletion(_ handler: @escaping @Sendable () async -> Void)
}

struct PlaybackAudioSession: Sendable {
    let activate: @Sendable () throws -> Void
    let deactivate: @Sendable (_ notifyOthers: Bool) -> Void
    static let system = Self(activate: {
        #if os(iOS) || os(watchOS)
        try AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
        try AVAudioSession.sharedInstance().setActive(true)
        #endif
    }, deactivate: { notifyOthers in
        #if os(iOS) || os(watchOS)
        try? AVAudioSession.sharedInstance().setActive(false,
            options: notifyOthers ? .notifyOthersOnDeactivation : [])
        #endif
    })
}

public actor SystemPlaybackAdapter: PlaybackAdapter {
    private var player: (any PlaybackHardware)?
    private var noteID: NoteID?
    private var generation: UUID?
    private var ownsAudioSession = false
    private let audioSession: PlaybackAudioSession
    private let makePlayer: @Sendable (URL) throws -> any PlaybackHardware
    public init() {
        audioSession = .system
        makePlayer = { try AVFoundationPlaybackHardware(url: $0) }
    }
    init(audioSession: PlaybackAudioSession,
         makePlayer: @escaping @Sendable (URL) throws -> any PlaybackHardware) {
        self.audioSession = audioSession; self.makePlayer = makePlayer
    }
    public func play(noteID: NoteID, url: URL) throws -> PlaybackProjection {
        stop()
        try audioSession.activate()
        ownsAudioSession = true
        do {
            let player = try makePlayer(url)
            let generation = UUID()
            self.player = player; self.noteID = noteID; self.generation = generation
            player.onCompletion { [weak self] in await self?.finished(generation: generation) }
            guard player.prepareToPlay(), player.play() else { throw WhimServiceError.audioUnavailable }
            return .init(noteID: noteID, isPlaying: true, elapsedSeconds: player.currentTime, durationSeconds: player.duration)
        } catch {
            stop()
            throw error
        }
    }
    public func stop() {
        generation = nil
        player?.stop(); player = nil; noteID = nil
        if ownsAudioSession {
            ownsAudioSession = false
            audioSession.deactivate(true)
        }
    }
    private func finished(generation: UUID) {
        guard self.generation == generation else { return }
        stop()
    }
    public func snapshot() -> PlaybackProjection? {
        guard let player, let noteID else { return nil }
        return .init(noteID: noteID, isPlaying: player.isPlaying, elapsedSeconds: player.currentTime, durationSeconds: player.duration)
    }
}

private final class AVFoundationPlaybackHardware: NSObject, PlaybackHardware, @unchecked Sendable {
    private let player: AVAudioPlayer
    private let lock = NSLock()
    private var completion: (@Sendable () async -> Void)?
    init(url: URL) throws {
        player = try AVAudioPlayer(contentsOf: url)
        super.init()
        player.delegate = self
    }
    var isPlaying: Bool { player.isPlaying }
    var currentTime: TimeInterval { player.currentTime }
    var duration: TimeInterval { player.duration }
    func prepareToPlay() -> Bool { player.prepareToPlay() }
    func play() -> Bool { player.play() }
    func stop() { player.stop() }
    func onCompletion(_ handler: @escaping @Sendable () async -> Void) { lock.withLock { completion = handler } }
    private func finish() {
        if let completion = lock.withLock({ completion }) { Task { await completion() } }
    }
}

extension AVFoundationPlaybackHardware: AVAudioPlayerDelegate {
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) { finish() }
    nonisolated func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) { finish() }
}
