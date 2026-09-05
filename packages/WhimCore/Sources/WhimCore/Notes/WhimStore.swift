import Foundation

public enum LeaseKind: String, Codable, Sendable {
    case delivery
    case titleEnrichment = "title_enrichment"
}

public protocol WhimStore: Sendable {
    func note(id: NoteID) async throws -> Note?
    func listNotes(filter: NoteFilter) async throws -> [NoteProjection]
    func saveFinalized(_ finalized: FinalizedRecording) async throws -> Note
    func apply(_ event: DeliveryEvent, to noteID: NoteID) async throws -> Delivery
    func acquireLease(
        _ kind: LeaseKind,
        noteID: NoteID,
        owner: UUID,
        until: Date
    ) async throws -> Bool
    func releaseLease(_ kind: LeaseKind, noteID: NoteID, owner: UUID) async throws
}
