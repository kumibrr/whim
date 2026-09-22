import Foundation

public enum CaptureEntryResult: Equatable, Sendable {
    case recording(RecordingProjection)
    case openAppForMicrophonePermission
}

public struct CaptureEntryService: Sendable {
    private let client: any WhimClient
    private let source: CaptureSource
    public init(client: any WhimClient, source: CaptureSource) {
        self.client = client; self.source = source
    }
    public func record() async throws -> CaptureEntryResult {
        do { return .recording(try await client.startRecording(source: source)) }
        catch WhimServiceError.permissionDenied { return .openAppForMicrophonePermission }
    }
    public func stop() async throws -> NoteProjection? { try await client.stopRecording() }
}
