import Foundation
import Observation
import WhimCore

/// Failed webhook Attempts shown in Settings, newest first.
@MainActor @Observable public final class WebhookErrorLog {
    public struct Entry: Equatable, Identifiable, Sendable {
        public let id: String
        public let noteID: NoteID?
        public let noteTitle: String
        public let failedAt: Date
        public let destination: SanitizedEndpointProjection
        /// "HTTP 400", or "Network error" when no response arrived.
        public let status: String
        /// The message the destination returned, or a description of why none exists.
        public let message: String
    }
    public private(set) var entries: [Entry] = []
    public private(set) var error: IPhoneError?
    private let client: any WhimClient

    public init(client: any WhimClient) { self.client = client }

    public func refresh() async {
        do { entries = try await client.webhookErrors().map(Self.entry); error = nil }
        catch is CancellationError {} catch { self.error = IPhoneError(error, operation: .settings) }
    }

    private static func entry(_ value: WebhookErrorProjection) -> Entry {
        let excerpt = value.message?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let fallback = value.responseStatusCode == nil ? "The destination could not be reached." : "The destination returned no message."
        return Entry(id: value.attemptID, noteID: UUID(uuidString: value.noteID).map(NoteID.init(rawValue:)),
            noteTitle: value.noteTitle, failedAt: value.failedAt,
            destination: value.destination,
            status: value.responseStatusCode.map { "HTTP \($0)" } ?? "Network error",
            message: excerpt.isEmpty ? fallback : excerpt)
    }
}
