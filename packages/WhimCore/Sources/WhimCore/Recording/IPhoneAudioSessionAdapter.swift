import AVFoundation
import Foundation

/// iPhone microphone session policy. Capture prefers an exclusive session; a Lock Screen or
/// Action-button start runs in the background, where iOS denies interrupting other audio,
/// so capture falls back to a mixable session instead of failing.
public struct IPhoneAudioSessionAdapter: Sendable {
    /// `AVAudioSession.ErrorCode.cannotInterruptOthers` ('!int').
    static let cannotInterruptOthers = NSError(domain: NSOSStatusErrorDomain, code: 0x21696E74)
    private let configure: @Sendable (_ mixable: Bool) throws -> Void
    private let setActive: @Sendable (Bool) throws -> Void
    public init() {
        configure = { mixable in
            #if os(iOS)
            // spokenAudio is a playback mode; physical iPhones can reject it for capture.
            if mixable {
                try AVAudioSession.sharedInstance().setCategory(.playAndRecord, mode: .default, options: [.mixWithOthers])
            } else {
                try AVAudioSession.sharedInstance().setCategory(.record, mode: .default)
            }
            #endif
        }
        setActive = { active in
            #if os(iOS)
            try AVAudioSession.sharedInstance().setActive(active,
                options: active ? [] : .notifyOthersOnDeactivation)
            #endif
        }
    }
    init(configure: @escaping @Sendable (_ mixable: Bool) throws -> Void,
         setActive: @escaping @Sendable (Bool) throws -> Void) {
        self.configure = configure; self.setActive = setActive
    }
    public func activate() throws {
        try configure(false)
        do { try setActive(true) }
        catch let error as NSError where error.code == Self.cannotInterruptOthers.code {
            try configure(true)
            try setActive(true)
        }
    }
    public func deactivate() { try? setActive(false) }
}
