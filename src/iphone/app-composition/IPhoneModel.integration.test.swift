import XCTest
import WhimCore
@testable import WhimIPhone

@MainActor final class IPhoneModelIntegrationTests: XCTestCase {
    func testMeasuredToneReachesRecordingPresentationAndResetsForNextSession() async throws {
        let harness = try WhimFacadeHarness()
        defer { harness.remove() }
        let model = IPhoneModel(client: harness.makeService(permissions: GrantedPermissions()))
        await model.start()
        defer { model.stop() }
        await model.startRecording()
        let samples = (0..<1600).map { Float(0.5 * sin(2 * .pi * 800 * Double($0) / 16000)) }
        let signal = RecordingSignal.measure(samples, sampleRate: 16000)
        await harness.recorder.emit(.signal(signal))
        await harness.recorder.emit(.elapsed(1))
        for _ in 0..<200 where model.elapsedSeconds != 1 { try await Task.sleep(for: .milliseconds(5)) }
        XCTAssertEqual(model.peakPowerDBFS, Double(signal.peakPowerDBFS), accuracy: 0.01)
        XCTAssertEqual(model.recordingTone, Double(signal.tone), accuracy: 0.015)
        let heldTone = model.recordingTone
        let heldPower = model.peakPowerDBFS
        await harness.recorder.emit(.elapsed(20))
        for _ in 0..<200 where model.elapsedSeconds != 20 { try await Task.sleep(for: .milliseconds(5)) }
        XCTAssertEqual(model.recordingTone, heldTone, "Elapsed time must not drive tone")
        XCTAssertEqual(model.peakPowerDBFS, heldPower, "Elapsed time must not drive volume")
        await model.discardRecording()
        await model.startRecording()
        XCTAssertEqual(model.recordingTone, 0)
        XCTAssertEqual(model.peakPowerDBFS, -160)
        await model.discardRecording()
    }

    func testRecordingClosesHistoryAndStopStaysIdle() async throws {
        let harness = try WhimFacadeHarness()
        defer { harness.remove() }
        let model = IPhoneModel(client: harness.makeService(permissions: GrantedPermissions()))
        await model.start()
        defer { model.stop() }
        model.openHistory()
        XCTAssertTrue(model.isHistoryPresented)
        await model.startRecording()
        XCTAssertFalse(model.isHistoryPresented)
        XCTAssertFalse(model.canBrowse)
        model.openHistory()
        XCTAssertFalse(model.isHistoryPresented)
        await model.stopRecording()
        XCTAssertTrue(model.canBrowse)
        XCTAssertFalse(model.isHistoryPresented)
    }

    func testWaveformDoesNotSurviveAudioRemoval() async throws {
        let harness = try WhimFacadeHarness()
        defer { harness.remove() }
        let client = harness.makeService(permissions: GrantedPermissions())
        _ = try await client.startRecording(source: .iphone)
        let saved = try await client.stopRecording()
        let id = try XCTUnwrap(saved).id
        let first = try await client.waveform(noteID: id)
        guard case .samples(let samples) = first else { return XCTFail("Expected audio samples") }
        XCTAssertEqual(samples.count, 64)
        XCTAssertTrue(samples.allSatisfy { $0.isFinite && (0...1).contains($0) })
        try harness.files.delete(noteID: id)
        let removed = try await client.waveform(noteID: id)
        XCTAssertEqual(removed, .unavailable)
    }

    func testClosingHistoryStopsInlinePlayback() async throws {
        let harness = try WhimFacadeHarness()
        defer { harness.remove() }
        let client = harness.makeService(playback: FacadePlayback(), permissions: GrantedPermissions())
        let model = IPhoneModel(client: client)
        await model.start()
        defer { model.stop() }
        await model.startRecording()
        await model.stopRecording()
        let id = try XCTUnwrap(model.notes.first).id
        model.openHistory()
        await model.playInline(id)
        XCTAssertEqual(model.playback?.noteID, id.rawValue.uuidString.lowercased())
        await model.closeHistory()
        XCTAssertNil(model.playback)
        let hardwareState = await client.playbackSnapshot()
        XCTAssertNil(hardwareState)
    }

    func testExternalRecordingClosesHistory() async throws {
        let harness = try WhimFacadeHarness()
        defer { harness.remove() }
        let client = harness.makeService(permissions: GrantedPermissions())
        let model = IPhoneModel(client: client)
        await model.start()
        defer { model.stop() }
        model.openHistory()
        _ = try await client.startRecording(source: .iphone)
        for _ in 0..<100 where model.recording == nil { try await Task.sleep(for: .milliseconds(5)) }
        XCTAssertNotNil(model.recording)
        XCTAssertFalse(model.isHistoryPresented)
        XCTAssertFalse(model.canBrowse)
        await model.discardRecording()
    }

    func testDeletingNoteDuringDecodeCannotRestoreWaveformAndDoesNotBlockCapture() async throws {
        let harness = try WhimFacadeHarness()
        defer { harness.remove() }
        let decoder = GatedWaveform()
        let client = harness.makeService(permissions: GrantedPermissions(), waveform: decoder)
        _ = try await client.startRecording(source: .iphone)
        let saved = try await client.stopRecording()
        let id = try XCTUnwrap(saved).id
        let query = Task { try await client.waveform(noteID: id) }
        await decoder.waitUntilStarted()
        _ = try await client.startRecording(source: .iphone)
        try await client.delete(noteID: id)
        await decoder.release()
        let result = try await query.value
        XCTAssertEqual(result, .unavailable)
        let active = try await client.activeRecording()
        XCTAssertNotNil(active)
        try await client.discardRecording()
    }

    func testStaleInlineSnapshotCannotReplaceNewPlayerOrReopenDismissedHistory() async throws {
        let harness = try WhimFacadeHarness()
        defer { harness.remove() }
        let hardware = InlinePlaybackHardware()
        let model = IPhoneModel(client: harness.makeService(playback: hardware, permissions: GrantedPermissions()))
        await model.start()
        defer { model.stop() }
        await model.startRecording(); await model.stopRecording()
        let first = try XCTUnwrap(model.notes.first).id
        await model.startRecording(); await model.stopRecording()
        let second = try XCTUnwrap(model.notes.first(where: { $0.id != first })).id
        model.openHistory()
        await model.playInline(first)
        await hardware.arm()
        let old = Task { await model.refreshInlinePlayback() }
        await hardware.waitUntilHeld()
        await model.playInline(second)
        await hardware.release()
        await old.value
        XCTAssertEqual(model.playback?.noteID, second.rawValue.uuidString.lowercased())
        await hardware.arm()
        let dismissed = Task { await model.refreshInlinePlayback() }
        await hardware.waitUntilHeld()
        await model.closeHistory()
        await hardware.release()
        await dismissed.value
        XCTAssertNil(model.playback)
        XCTAssertFalse(model.isHistoryPresented)
    }

    func testNavigationCannotReappearAfterRecordingStartsDuringPlayerCleanup() async throws {
        let harness = try WhimFacadeHarness()
        defer { harness.remove() }
        let playback = NavigationPlayback()
        let client = harness.makeService(playback: playback, permissions: GrantedPermissions())
        let model = IPhoneModel(client: client)
        await model.start()
        defer { model.stop() }
        await playback.arm()
        let navigation = Task { await model.prepareForNavigation() }
        await playback.waitUntilHeld()
        _ = try await client.startRecording(source: .iphone)
        await playback.release()
        let mayNavigate = await navigation.value
        XCTAssertFalse(mayNavigate)
        XCTAssertNotNil(model.recording)
        await model.discardRecording()
    }

    func testFinishedExternalRecordingStillCancelsPendingNavigation() async throws {
        let harness = try WhimFacadeHarness()
        defer { harness.remove() }
        let playback = NavigationPlayback()
        let client = harness.makeService(playback: playback, permissions: GrantedPermissions())
        let model = IPhoneModel(client: client)
        await model.start()
        defer { model.stop() }
        await playback.arm()
        let navigation = Task { await model.prepareForNavigation() }
        await playback.waitUntilHeld()
        _ = try await client.startRecording(source: .iphone)
        try await client.discardRecording()
        await model.refresh()
        await playback.release()
        let mayNavigate = await navigation.value
        XCTAssertFalse(mayNavigate, "Finishing capture must not revive navigation canceled at its start")
    }

    func testInactiveInlinePlayerDefersSnapshotsUntilForeground() async throws {
        let harness = try WhimFacadeHarness()
        defer { harness.remove() }
        let hardware = InlinePlaybackHardware()
        let model = IPhoneModel(client: harness.makeService(playback: hardware, permissions: GrantedPermissions()))
        await model.start()
        defer { model.stop() }
        await model.startRecording(); await model.stopRecording()
        let id = try XCTUnwrap(model.notes.first).id
        model.openHistory()
        await model.playInline(id)
        await model.setSceneActive(false)
        await hardware.stop()
        await model.refreshInlinePlayback()
        XCTAssertTrue(model.playback?.isPlaying == true, "An inactive presentation does not poll hardware")
        await model.setSceneActive(true)
        XCTAssertNil(model.playback, "Foreground reconciles playback completion")
        await model.closeHistory()
    }

    func testLaunchCaptureAndDiscardReflectCanonicalState() async throws {
        let harness = try WhimFacadeHarness()
        defer { harness.remove() }
        let model = IPhoneModel(client: harness.makeService(permissions: GrantedPermissions()))
        await model.start()
        defer { model.stop() }
        XCTAssertNotNil(model.settings)
        await model.startRecording()
        XCTAssertNotNil(model.recording)
        await model.startRecording()
        let count = await harness.recorder.startCount
        XCTAssertEqual(count, 1)
        await model.discardRecording()
        XCTAssertNil(model.recording)
        XCTAssertTrue(model.notes.isEmpty)
    }
    func testStopCreatesNoteAndResetClearsAllPresentationState() async throws {
        let harness = try WhimFacadeHarness()
        defer { harness.remove() }
        let model = IPhoneModel(client: harness.makeService(permissions: GrantedPermissions()))
        await model.start()
        defer { model.stop() }
        await model.startRecording()
        await model.stopRecording()
        XCTAssertEqual(model.notes.count, 1)
        XCTAssertNil(model.recording)
        await model.perform { try await model.client.completeOnboarding() }
        XCTAssertEqual(model.settings?.onboardingCompleted, true)
        await model.perform { try await model.client.reset() }
        XCTAssertTrue(model.notes.isEmpty)
        XCTAssertEqual(model.settings?.onboardingCompleted, false)
    }
    func testSlowRetryDoesNotPreventStartingAndStoppingAnotherRecording() async throws {
        let harness = try WhimFacadeHarness(responses: [.init(statusCode: 400), .init(statusCode: 204)])
        defer { harness.remove() }
        _ = try await harness.configuration.save(.init(endpoint: "https://example.com/whim"))
        let model = IPhoneModel(client: harness.makeService(permissions: GrantedPermissions()))
        await model.start()
        defer { model.stop() }
        await model.startRecording()
        await model.stopRecording()
        for _ in 0..<100 where model.notes.first?.status != .failed { try await Task.sleep(for: .milliseconds(5)) }
        let id = try XCTUnwrap(model.notes.first).id
        await harness.transport.suspendResponses()
        let retry = Task { await model.perform { try await model.client.retry(noteID: id) } }
        await harness.transport.waitForRequestCount(2)
        await model.startRecording()
        XCTAssertNotNil(model.recording, "A network request must not block capture")
        await model.stopRecording()
        XCTAssertNil(model.recording)
        await harness.transport.resumeResponses()
        await retry.value
        XCTAssertEqual(model.notes.count, 2)
    }
    func testForegroundRefreshClearsResolvedPermissionError() async throws {
        let harness = try WhimFacadeHarness()
        defer { harness.remove() }
        let permissions = MutablePermissions()
        let model = IPhoneModel(client: harness.makeService(permissions: permissions))
        await model.start()
        defer { model.stop() }
        await model.startRecording()
        XCTAssertNotNil(model.error)
        await permissions.grant()
        await model.refresh()
        XCTAssertEqual(model.settings?.permissions.microphone, .granted)
        XCTAssertNil(model.error)
    }
    func testOptionalPermissionPromptCanBeDeferred() async throws {
        let harness = try WhimFacadeHarness()
        defer { harness.remove() }
        let model = IPhoneModel(client: harness.makeService(permissions: GrantedPermissions()))
        await model.start()
        defer { model.stop() }
        await model.startRecording()
        await model.stopRecording()
        for _ in 0..<100 where !model.offersContextualPermissions { try await Task.sleep(for: .milliseconds(5)) }
        XCTAssertTrue(model.offersContextualPermissions)
        model.dismissContextualPermissions()
        XCTAssertFalse(model.offersContextualPermissions)
    }
    func testDeniedPermissionShowsSanitizedError() async throws {
        let harness = try WhimFacadeHarness()
        defer { harness.remove() }
        let model = IPhoneModel(client: harness.makeService(permissions: DeniedFacadePermissions()))
        await model.start()
        defer { model.stop() }
        await model.startRecording()
        XCTAssertNil(model.recording)
        XCTAssertEqual(model.error?.message, "Microphone access is required. Open Settings to allow access.")
    }
    func testExternalCaptureUpdatesObserverAndRestartsWithoutLosingState() async throws {
        let harness = try WhimFacadeHarness()
        defer { harness.remove() }
        let client = harness.makeService(permissions: GrantedPermissions())
        let model = IPhoneModel(client: client)
        await model.start()
        await model.start()
        _ = try await client.startRecording(source: .iphone)
        for _ in 0..<100 where model.recording == nil { try await Task.sleep(for: .milliseconds(5)) }
        XCTAssertNotNil(model.recording)
        model.stop()
        _ = try await client.stopRecording()
        await model.start()
        defer { model.stop() }
        XCTAssertNil(model.recording)
        XCTAssertEqual(model.notes.count, 1)
        let note = try XCTUnwrap(model.notes.first)
        try await client.delete(noteID: note.id)
        for _ in 0..<100 where !model.notes.isEmpty { try await Task.sleep(for: .milliseconds(5)) }
        XCTAssertTrue(model.notes.isEmpty)
    }
    func testResetEventsCannotBeUndoneByAnOlderSuspendedSnapshot() async throws {
        let harness = try WhimFacadeHarness()
        defer { harness.remove() }
        let playback = GatedPlayback()
        let client = harness.makeService(playback: playback, permissions: GrantedPermissions())
        let model = IPhoneModel(client: client)
        await model.start()
        defer { model.stop() }
        await model.startRecording(); await model.stopRecording()
        await playback.arm(2)
        let loading = Task { await model.refresh() }
        await playback.waitForSnapshot(1)
        try await client.reset()
        for _ in 0..<100 where !model.notes.isEmpty { try await Task.sleep(for: .milliseconds(5)) }
        XCTAssertTrue(model.notes.isEmpty)
        await playback.release(1)
        await playback.waitForSnapshot(2)
        XCTAssertTrue(model.notes.isEmpty, "An older snapshot must not resurrect the deleted Note even temporarily")
        await playback.release(2)
        await loading.value
        XCTAssertEqual(model.settings?.onboardingCompleted, false)
    }
    func testStoppedObserversCannotOverwriteRestartedPresentation() async throws {
        let harness = try WhimFacadeHarness()
        defer { harness.remove() }
        let playback = GatedPlayback()
        let client = harness.makeService(playback: playback, permissions: GrantedPermissions())
        let model = IPhoneModel(client: client)
        await model.start()
        await playback.arm()
        let old = Task { await model.refresh() }
        await playback.waitForSnapshot(1)
        model.stop()
        _ = try await client.startRecording(source: .iphone)
        await model.start()
        defer { model.stop() }
        XCTAssertNotNil(model.recording)
        await playback.release(1)
        await old.value
        XCTAssertNotNil(model.recording)
        try await client.discardRecording()
    }
    func testConcurrentRefreshesRetainFinalResetState() async throws {
        let harness = try WhimFacadeHarness()
        defer { harness.remove() }
        let model = IPhoneModel(client: harness.makeService(permissions: GrantedPermissions()))
        await model.start()
        defer { model.stop() }
        await model.startRecording()
        await model.stopRecording()
        let first = Task { await model.refresh() }
        let second = Task { await model.refresh() }
        await model.perform { try await model.client.reset() }
        await first.value; await second.value
        XCTAssertTrue(model.notes.isEmpty)
        XCTAssertNil(model.recording)
        XCTAssertFalse(model.isRefreshing)
        XCTAssertEqual(model.settings?.onboardingCompleted, false)
    }
    func testNewPresentationInstanceReadsExistingNotesPreferencesAndAudio() async throws {
        let harness = try WhimFacadeHarness()
        defer { harness.remove() }
        let original = harness.makeService(playback: FacadePlayback(), permissions: GrantedPermissions())
        _ = try await original.startRecording(source: .iphone)
        let saved = try await original.stopRecording()
        let id = try XCTUnwrap(saved).id
        try await original.updatePreferences(.init(retentionPolicy: .never, transcriptionEnabled: false, transcriptionLocaleIdentifier: "es-ES"))
        let replacement = IPhoneModel(client: harness.makeService(playback: FacadePlayback(), permissions: GrantedPermissions()))
        await replacement.start()
        defer { replacement.stop() }
        XCTAssertEqual(replacement.notes.map(\.id), [id])
        XCTAssertEqual(replacement.settings?.preferences.retentionPolicy, .never)
        XCTAssertEqual(replacement.settings?.preferences.transcriptionLocaleIdentifier, "es-ES")
        let playback = try await replacement.client.playNote(id)
        XCTAssertTrue(playback.isPlaying)
    }

}

actor GrantedPermissions: PermissionAdapter {
    func status(_ kind: PermissionKind) -> PermissionStatus { .granted }
    func request(_ kind: PermissionKind) -> PermissionStatus { .granted }
    func openSettings() {}
}

@MainActor final class LegacyUpgradeIntegrationTests: XCTestCase {
    func testPreMigrationStoreAndPreferencesOpenInSwiftUIPresentation() async throws {
        let fixture = try XCTUnwrap(Bundle.module.url(forResource: "legacy-v1", withExtension: nil, subdirectory: "Fixtures"))
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.copyItem(at: fixture, to: root)
        defer { try? FileManager.default.removeItem(at: root) }
        // Relocation is fixture setup only: the app retains its existing paths unchanged.
        try relocateLegacyAudio(root: root)
        let suite = "whim.upgrade." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let domain = try PropertyListSerialization.propertyList(from: Data(contentsOf: root.appendingPathComponent("preferences.plist")), format: nil)
        defaults.setPersistentDomain(try XCTUnwrap(domain as? [String: Any]), forName: suite)
        let harness = try WhimFacadeHarness(root: root)
        let credentials = try JSONDecoder().decode(StoredWebhookCredentials.self, from: Data(contentsOf: root.appendingPathComponent("credentials.json")))
        let revision = try JSONDecoder().decode(ConfigurationRevisionID.self, from: Data(contentsOf: root.appendingPathComponent("revision.json")))
        await harness.credentials.save(credentials, for: revision)
        let preferences = try UserDefaultsPreferenceStore(suiteName: suite)
        let model = IPhoneModel(client: harness.makeService(isConnected: { false }, playback: FacadePlayback(), permissions: GrantedPermissions(), preferences: preferences, onboarding: UserDefaultsOnboardingStore(suiteName: suite)))
        await model.start()
        defer { model.stop() }
        XCTAssertEqual(model.notes.count, 2)
        XCTAssertEqual(model.notes.filter { $0.status == .sent }.count, 1)
        XCTAssertEqual(model.notes.filter { $0.status == .queued }.count, 1)
        XCTAssertEqual(model.settings?.onboardingCompleted, true)
        XCTAssertEqual(model.settings?.preferences.retentionPolicy, .never)
        XCTAssertEqual(model.settings?.preferences.transcriptionEnabled, false)
        XCTAssertEqual(model.settings?.preferences.transcriptionLocaleIdentifier, "es-ES")
        XCTAssertEqual(model.settings?.webhook?.hasBearerToken, true)
        XCTAssertEqual(model.settings?.webhook?.hasHMACSecret, true)
        for note in model.notes {
            let detail = try await model.client.note(id: note.id)
            XCTAssertEqual(detail?.hasLocalAudio, true)
            let playback = try await model.client.playNote(note.id)
            XCTAssertTrue(playback.isPlaying)
            await model.client.stopPlayback()
        }
    }
}
