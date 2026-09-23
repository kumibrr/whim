import AppIntents
import WhimCore

struct RecordWhimIntent: AudioRecordingIntent {
    static let title: LocalizedStringResource = "Record a Whim"
    static let description = IntentDescription("Start a Recording Session in Whim.")
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
            result = try await CaptureEntryService(client: client, source: captureSource).record()
        } catch {
            throw needsToContinueInForegroundError("Recording could not start. Open Whim to check microphone access and Live Activity settings.")
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
