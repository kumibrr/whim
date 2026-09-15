import AVFoundation
import Foundation

/// Watch microphone session policy. The audio background mode keeps an ongoing capture
/// eligible during wrist-down; no workout or unrelated extended-runtime session is created.
public struct WatchAudioSessionAdapter: Sendable {
    private let configure: @Sendable () throws -> Void
    private let setActive: @Sendable (Bool) throws -> Void
    public init() {
        configure = {
            #if os(watchOS)
            try AVAudioSession.sharedInstance().setCategory(.record, mode: .default)
            #endif
        }
        setActive = { active in
            #if os(watchOS)
            try AVAudioSession.sharedInstance().setActive(active,
                options: active ? [] : .notifyOthersOnDeactivation)
            #endif
        }
    }
    init(configure: @escaping @Sendable () throws -> Void,
         setActive: @escaping @Sendable (Bool) throws -> Void) {
        self.configure = configure; self.setActive = setActive
    }
    public func activate() throws { try configure(); try setActive(true) }
    public func deactivate() { try? setActive(false) }
}
