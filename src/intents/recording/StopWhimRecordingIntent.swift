import AppIntents
import WhimCore

struct StopWhimRecordingIntent: AudioRecordingIntent {
    static let title: LocalizedStringResource = "Stop Whim Recording"
    static let description = IntentDescription("Finish the active Recording Session.")
    static var openAppWhenRun: Bool { false }
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
        let client = try await runtime.service()
        _ = try await CaptureEntryService(client: client, source: captureSource).stop()
        return .result()
    }
}

#if os(iOS)
extension StopWhimRecordingIntent: LiveActivityIntent {}
#endif
