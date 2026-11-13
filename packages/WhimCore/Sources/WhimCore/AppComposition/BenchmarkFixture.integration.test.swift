#if DEBUG
import Foundation
import XCTest
@testable import WhimCore

final class BenchmarkFixtureIntegrationTests: XCTestCase {
    func testPopulatedFixtureUsesRealNotesFilesAndAnIsolatedCompletedOnboardingState() async throws {
        let id = UUID()
        let request = try XCTUnwrap(BenchmarkFixture.from(arguments: ["app", "-WhimBenchmarkID", id.uuidString, "-WhimBenchmarkNotes", "1000", "-WhimBenchmarkSetup"]))
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("WhimBenchmarkFixtureTests/" + id.uuidString)
        defer { try? FileManager.default.removeItem(at: root); UserDefaults.standard.removePersistentDomain(forName: request.suiteName) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let store = try SQLiteWhimStore.open(at: root.appendingPathComponent("whim.sqlite"))
        let files = try AudioFileStore(root: root.appendingPathComponent("Audio"), closeWriter: { _ in })
        let audio = try XCTUnwrap(Bundle.module.url(forResource: "configuration-test-fixture", withExtension: "m4a", subdirectory: "Fixtures"))
        try await request.prepare(store: store, files: files, fixture: audio)
        try await request.prepare(store: store, files: files, fixture: audio)
        let notes = try await store.listNotes(filter: .all)
        XCTAssertEqual(notes.count, 1000)
        XCTAssertEqual(notes.first?.title, "Benchmark Note 0999")
        XCTAssertTrue(notes.allSatisfy { $0.hasLocalAudio })
        let saved = try await store.note(id: notes[0].id)
        let first = try XCTUnwrap(saved)
        XCTAssertTrue(FileManager.default.fileExists(atPath: first.audioURL.path))
        XCTAssertTrue(UserDefaultsOnboardingStore(suiteName: request.suiteName).isComplete())
        XCTAssertFalse(try UserDefaultsPreferenceStore(suiteName: request.suiteName).load().transcriptionEnabled)
        XCTAssertNotEqual(request.suiteName, WhimProductionComposition.appGroupIdentifier)
    }

    func testEmptyFixtureAndMalformedRequestsCannotFallThroughToProductionState() throws {
        XCTAssertNil(try BenchmarkFixture.from(arguments: ["app"]))
        for args in [["-WhimBenchmarkID"], ["-WhimBenchmarkID", "../escape"],
                     ["-WhimBenchmarkID", UUID().uuidString, "-WhimBenchmarkNotes", "999"],
                     ["-WhimBenchmarkID", UUID().uuidString]] {
            XCTAssertThrowsError(try BenchmarkFixture.from(arguments: ["app"] + args))
        }
        let request = try XCTUnwrap(BenchmarkFixture.from(arguments: ["app", "-WhimBenchmarkID", UUID().uuidString, "-WhimBenchmarkNotes", "0"]))
        XCTAssertEqual(request.noteCount, 0)
        XCTAssertFalse(request.setup)
    }
}

#endif
