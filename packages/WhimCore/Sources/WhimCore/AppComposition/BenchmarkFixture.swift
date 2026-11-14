#if DEBUG
import Foundation

/// Deterministic, isolated installed-app benchmark setup. Never part of Release.
public struct BenchmarkFixture: Sendable {
    public let id: UUID
    public let noteCount: Int
    public let setup: Bool
    public var suiteName: String { WhimProductionComposition.appGroupIdentifier + ".benchmark." + id.uuidString }
    public var root: URL { FileManager.default.temporaryDirectory.appendingPathComponent("WhimPerformance/" + id.uuidString) }

    public static func from(arguments: [String]) throws -> Self? {
        guard let index = arguments.firstIndex(of: "-WhimBenchmarkID") else { return nil }
        guard arguments.indices.contains(index + 1), let id = UUID(uuidString: arguments[index + 1]),
              let countIndex = arguments.firstIndex(of: "-WhimBenchmarkNotes"), arguments.indices.contains(countIndex + 1),
              let count = Int(arguments[countIndex + 1]), [0, 1000].contains(count) else {
            throw WhimServiceError.setupRequired("Invalid isolated benchmark fixture.")
        }
        return .init(id: id, noteCount: count, setup: arguments.contains("-WhimBenchmarkSetup"))
    }

    public func prepare(store: any WhimStore, files: AudioFileStore, fixture: URL) async throws {
        guard setup else { return }
        // The untimed setup may be retried. Fixed IDs keep fixture population
        // idempotent, without bypassing normal storage/projection behavior.
        for index in 0..<noteCount {
            let uuid = UUID(uuidString: String(format: "00000000-0000-4000-8000-%012d", index))!
            let noteID = NoteID(rawValue: uuid)
            if try await store.note(id: noteID) != nil { continue }
            let audio = files.audioURL(for: noteID)
            if !FileManager.default.fileExists(atPath: audio.path) { try FileManager.default.copyItem(at: fixture, to: audio) }
            _ = try await store.saveFinalized(.init(id: noteID, recordingSessionID: .init(),
                title: String(format: "Benchmark Note %04d", index), titleSource: .timestamp,
                createdAt: Date(timeIntervalSince1970: 1_700_000_000 + Double(index)), duration: 3,
                source: .iphone, captureOutcome: .completed, requiresReview: false, audioURL: audio))
        }
        UserDefaultsOnboardingStore(suiteName: suiteName).complete()
        try UserDefaultsPreferenceStore(suiteName: suiteName).save(.init(retentionPolicy: .never,
            transcriptionEnabled: false, transcriptionLocaleIdentifier: nil))
    }
}

struct BenchmarkPermissions: PermissionAdapter {
    func status(_ kind: PermissionKind) async -> PermissionStatus { .granted }
    func request(_ kind: PermissionKind) async throws -> PermissionStatus { .granted }
    func openSettings() async throws {}
}
#endif
