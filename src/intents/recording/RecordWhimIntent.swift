import AppIntents
import WhimCore

struct RecordWhimIntent: AudioRecordingIntent {
    static let title: LocalizedStringResource = "Record a Whim"
    static var description: IntentDescription {
        #if os(iOS)
        IntentDescription("Start a Recording Session, or stop and send the active recording in Whim.")
        #else
        IntentDescription("Start a Recording Session in Whim.")
        #endif
    }
    static var openAppWhenRun: Bool {
        #if os(watchOS)
        true
        #else
        false
        #endif
    }
    static var authenticationPolicy: IntentAuthenticationPolicy { .alwaysAllowed }
    @Dependency(default: WhimRuntime.shared) private var runtime: WhimRuntime
    init() {}
    init(runtime: WhimRuntime) { self.runtime = runtime }
    private var captureSource: CaptureSource {
        #if os(watchOS)
        .appleWatch
        #else
        .iphone
        #endif
    }
    @MainActor func perform() async throws -> some IntentResult {
        #if WHIM_WIDGET_EXTENSION
        try requireRecordingHostProcess()
        return .result()
        #else
        let result: CaptureEntryResult
        do {
            let client = try await runtime.service()
            let entry = CaptureEntryService(client: client, source: captureSource)
            #if os(iOS)
            if try await client.activeRecording() != nil {
                _ = try await entry.stop()
                return .result()
            }
            #endif
            result = try await entry.record()
        } catch {
            throw needsToContinueInForegroundError("Whim could not update the recording. Open Whim to check microphone access and Live Activity settings.")
        }
        if case .openAppForMicrophonePermission = result {
            throw needsToContinueInForegroundError("Open Whim to allow microphone access and start recording.")
        }
        return .result()
        #endif
    }
}

#if os(iOS)
/// Routes the Lock Screen control to the app's microphone owner instead of the widget extension.
extension RecordWhimIntent: LiveActivityIntent {}
#endif

#if !WHIM_WIDGET_EXTENSION
extension RecordWhimIntent: ForegroundContinuableIntent {}
#else
private func requireRecordingHostProcess() throws {
    throw WhimServiceError.setupRequired("Open Whim to start recording.")
}
#endif
