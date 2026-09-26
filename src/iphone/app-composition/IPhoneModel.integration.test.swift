import XCTest
import WhimCore
@testable import WhimIPhone

@MainActor final class IPhoneModelIntegrationTests: XCTestCase {
    func testRepeatedSystemRecordKeepsElapsedTime() async throws {
        let harness = try WhimFacadeHarness()
        defer { harness.remove() }
        let client = harness.makeService(permissions: GrantedPermissions())
        let model = IPhoneModel(client: client)
        await model.start()
        _ = try await client.startRecording(source: .iphone)
        await harness.recorder.emit(.elapsed(20))
        for _ in 0..<200 where model.elapsedSeconds != 20 { try await Task.sleep(for: .milliseconds(5)) }
        let events = client.events()
        _ = try await CaptureEntryService(client: client, source: .iphone).record()
        var iterator = events.makeAsyncIterator()
        _ = await iterator.next()
        // Let the independently subscribed presentation consume the same event.
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(model.elapsedSeconds, 20)
        try await client.discardRecording()
        model.stop()
    }

    func testCollapsedFailurePreservesRecoveryAndClearsWhenResolved() async throws {
        let harness = try WhimFacadeHarness()
        defer { harness.remove() }
        let permissions = MutablePermissions()
        let model = IPhoneModel(client: harness.makeService(permissions: permissions))
        await model.start()
        defer { model.stop() }
        await model.startRecording()
        let failure = try XCTUnwrap(model.visibleFailure)
        XCTAssertEqual(model.failureCount, 1, "Permission denial is one issue, even after failed capture")
        model.collapseFailures()
        XCTAssertTrue(model.areFailuresCollapsed)
        XCTAssertEqual(model.visibleFailure, failure)
        await model.refresh()
        XCTAssertTrue(model.areFailuresCollapsed, "Refreshing the same issue must not reopen it")
        model.expandFailures()
        XCTAssertFalse(model.areFailuresCollapsed)
        XCTAssertEqual(model.visibleFailure?.action, .microphoneSettings)
        model.collapseFailures()
        await permissions.grant()
        await model.refresh()
        XCTAssertEqual(model.failureCount, 0)
        XCTAssertFalse(model.areFailuresCollapsed)
    }

    func testNewFailureExpandsCardAndCountsIndependentIssues() async throws {
        let harness = try WhimFacadeHarness()
        defer { harness.remove() }
        let model = IPhoneModel(client: harness.makeService(permissions: DeniedFacadePermissions()))
        await model.start()
        defer { model.stop() }
        model.collapseFailures()
        await model.perform { throw ConfigurationTestError.missingConfiguration }
        XCTAssertEqual(model.failureCount, 2)
        XCTAssertFalse(model.areFailuresCollapsed)
        XCTAssertEqual(model.visibleFailure?.action, .microphoneSettings)
        model.collapseFailures()
        XCTAssertTrue(model.areFailuresCollapsed)
        await model.perform {}
        XCTAssertEqual(model.failureCount, 1)
        XCTAssertTrue(model.areFailuresCollapsed, "Resolving one issue keeps the remaining notification collapsed")
    }

    func testMaintenanceFailureKeepsExistingAndNewNotesVisibleAndPlayable() async throws {
        let harness = try WhimFacadeHarness()
        defer { harness.remove() }
        let id = NoteID()
        let url = harness.files.audioURL(for: id)
        try writeAudioFixture(to: url)
        _ = try await harness.store.saveFinalized(FinalizedRecording(id: id, recordingSessionID: RecordingSessionID(),
            title: "Saved Note", titleSource: .timestamp, createdAt: Date(), duration: 1, source: .iphone,
            captureOutcome: .completed, requiresReview: false, audioURL: url))
        let model = IPhoneModel(client: harness.makeService(playback: FacadePlayback(), permissions: GrantedPermissions(),
            recoveryFiles: FailingRecoveryOwnership(base: harness.files)))
        await model.start()
        for _ in 0..<100 where model.maintenanceError == nil { try await Task.sleep(for: .milliseconds(5)) }
        XCTAssertNotNil(model.maintenanceError)
        XCTAssertNil(model.historyError)
        XCTAssertTrue(model.notes.contains { $0.id == id })
        model.openHistory()
        await model.playInline(id)
        XCTAssertEqual(model.playback?.noteID, id.rawValue.uuidString.lowercased())
        await model.closeHistory()
        await model.startRecording()
        await model.stopRecording()
        let newest = try XCTUnwrap(model.notes.first { $0.id != id }).id
        model.openHistory()
        await model.playInline(newest)
        XCTAssertEqual(model.playback?.noteID, newest.rawValue.uuidString.lowercased())
        XCTAssertNil(model.error)
        XCTAssertEqual(model.notes.count, 2)
        model.stop()
    }

    func testDeletingDuringMaintenanceRestartsRemainingRecovery() async throws {
        let harness = try WhimFacadeHarness()
        defer { harness.remove() }
        let id = NoteID()
        let url = harness.files.audioURL(for: id)
        try writeAudioFixture(to: url)
        _ = try await harness.store.saveFinalized(FinalizedRecording(id: id, recordingSessionID: RecordingSessionID(),
            title: "Delete me", titleSource: .timestamp, createdAt: Date(), duration: 1, source: .iphone,
            captureOutcome: .completed, requiresReview: false, audioURL: url))
        let orphan = RecordingSession(id: RecordingSessionID(), noteID: NoteID(), createdAt: Date(), source: .iphone)
        try await harness.store.saveRecordingSession(orphan)
        try writeAudioFixture(to: harness.files.temporaryURL(for: orphan.id))
        let entered = expectation(description: "Recovery entered")
        let cancelled = expectation(description: "Delete cancelled recovery")
        let gate = RecoveryClaimGate(entered: entered, cancelled: cancelled)
        let client = harness.makeService(permissions: GrantedPermissions(),
            recoveryFiles: FailingRecoveryOwnership(base: harness.files, beforeClaim: { try gate.wait() }))
        let model = IPhoneModel(client: client)
        await model.start()
        await fulfillment(of: [entered], timeout: 1)
        let deletion = Task { try await client.delete(noteID: id) }
        await fulfillment(of: [cancelled], timeout: 1)
        gate.release()
        try await deletion.value
        for _ in 0..<100 where !model.notes.contains(where: { $0.id == orphan.noteID }) {
            try await Task.sleep(for: .milliseconds(5))
        }
        XCTAssertTrue(model.notes.contains { $0.id == orphan.noteID && $0.requiresReview })
        XCTAssertFalse(model.notes.contains { $0.id == id })
        model.stop()
    }

    func testClosingHistoryClearsItsPlaybackFailure() async throws {
        let harness = try WhimFacadeHarness()
        defer { harness.remove() }
        let model = IPhoneModel(client: harness.makeService(playback: FailsFirstPlayback(), permissions: GrantedPermissions()))
        await model.start()
        await model.startRecording(); await model.stopRecording()
        model.openHistory()
        await model.playInline(try XCTUnwrap(model.notes.first).id)
        XCTAssertEqual(model.error?.recovery.operation, .playback)
        await model.closeHistory()
        XCTAssertNil(model.error)
        model.stop()
    }

    func testPlaybackFailureRetriesTheSameNoteInsideHistory() async throws {
        let harness = try WhimFacadeHarness()
        defer { harness.remove() }
        let model = IPhoneModel(client: harness.makeService(playback: FailsFirstPlayback(), permissions: GrantedPermissions()))
        await model.start()
        await model.startRecording()
        await model.stopRecording()
        let id = try XCTUnwrap(model.notes.first).id
        model.openHistory()
        await model.playInline(id)
        XCTAssertEqual(model.visibleFailure?.operation, .playback)
        XCTAssertTrue(model.isHistoryPresented)
        await model.retryVisibleFailure()
        XCTAssertEqual(model.playback?.noteID, id.rawValue.uuidString.lowercased())
        XCTAssertNil(model.error)
        XCTAssertTrue(model.isHistoryPresented)
        model.stop()
    }

    func testPlaybackFailureBelongsToItsNoteUntilPlaybackSucceeds() async throws {
        let harness = try WhimFacadeHarness()
        defer { harness.remove() }
        let model = IPhoneModel(client: harness.makeService(playback: FailsFirstPlayback(), permissions: GrantedPermissions()))
        await model.start()
        await model.startRecording(); await model.stopRecording()
        await model.startRecording(); await model.stopRecording()
        let failed = try XCTUnwrap(model.notes.first).id
        let other = try XCTUnwrap(model.notes.last).id
        model.openHistory()
        await model.playInline(failed)
        XCTAssertNotNil(model.playbackFailure(for: failed))
        XCTAssertEqual(model.playbackFailure(for: failed), model.error?.message)
        XCTAssertNil(model.playbackFailure(for: other))
        await model.playInline(failed)
        XCTAssertNil(model.playbackFailure(for: failed))
        model.stop()
    }

    func testRecordingEventDuringStartupDoesNotWithholdCaptureReadiness() async throws {
        let harness = try WhimFacadeHarness()
        defer { harness.remove() }
        let permissions = SlowPresentationPermissions(blockFirstMicrophone: true)
        let client = harness.makeService(permissions: permissions)
        let model = IPhoneModel(client: client)
        let starting = Task { await model.start() }
        await permissions.waitUntilMicrophoneBlocked()
        _ = try await client.startRecording(source: .iphone)
        for _ in 0..<100 where model.recording == nil { try await Task.sleep(for: .milliseconds(5)) }
        XCTAssertNotNil(model.recording)
        await permissions.releaseMicrophone()
        await permissions.waitUntilBlocked()
        XCTAssertTrue(model.captureReady, "A newer recording event must not discard readiness or permission")
        XCTAssertEqual(model.startupState?.microphone, .granted)
        await permissions.release()
        await starting.value
        await model.discardRecording()
        model.stop()
    }

    func testCompletingOnboardingDoesNotJoinSlowSettingsRefresh() async throws {
        let harness = try WhimFacadeHarness()
        defer { harness.remove() }
        let permissions = SlowPresentationPermissions()
        let model = IPhoneModel(client: harness.makeService(permissions: permissions))
        let starting = Task { await model.start() }
        await permissions.waitUntilBlocked()
        let completed = expectation(description: "Onboarding routes before optional settings finish")
        let completion = Task { @MainActor in
            await model.perform { try await model.client.completeOnboarding() }
            XCTAssertTrue(model.onboardingCompleted)
            XCTAssertFalse(model.isPending)
            completed.fulfill()
        }
        await fulfillment(of: [completed], timeout: 1)
        await permissions.release()
        await completion.value; await starting.value
        model.stop()
    }

    func testRetryingUnrelatedFailureNeverStartsRecording() async throws {
        let harness = try WhimFacadeHarness()
        defer { harness.remove() }
        let model = IPhoneModel(client: harness.makeService(permissions: GrantedPermissions()))
        await model.start()
        await model.perform { throw WhimStoreError.missingNote }
        await model.retryVisibleFailure()
        XCTAssertNil(model.recording)
        let starts = await harness.recorder.startCount
        XCTAssertEqual(starts, 0)
        model.stop()
    }

    func testRetryingInlinePlaybackFailureNeverStartsRecording() async throws {
        let harness = try WhimFacadeHarness()
        defer { harness.remove() }
        let client = harness.makeService(playback: FacadePlayback(), permissions: GrantedPermissions())
        _ = try await client.startRecording(source: .iphone)
        _ = try await client.stopRecording()
        let model = IPhoneModel(client: client)
        await model.start()
        let id = try XCTUnwrap(model.notes.first).id
        try harness.files.delete(noteID: id)
        model.openHistory()
        await model.playInline(id)
        XCTAssertNotNil(model.error)
        await model.retryVisibleFailure()
        XCTAssertNil(model.recording)
        let starts = await harness.recorder.startCount
        XCTAssertEqual(starts, 1)
        model.stop()
    }

    func testCapturePresentationDoesNotWaitForOptionalSettings() async throws {
        let harness = try WhimFacadeHarness()
        defer { harness.remove() }
        let permissions = SlowPresentationPermissions()
        let model = IPhoneModel(client: harness.makeService(permissions: permissions))
        let starting = Task { await model.start() }
        await permissions.waitUntilBlocked()
        let captured = expectation(description: "Capture UI ready while optional settings are suspended")
        let capture = Task { @MainActor in
            await model.startRecording()
            XCTAssertNotNil(model.recording)
            XCTAssertFalse(model.isRecordingPending)
            await model.stopRecording()
            XCTAssertNil(model.recording)
            captured.fulfill()
        }
        await fulfillment(of: [captured], timeout: 1)
        await permissions.release()
        await starting.value
        await capture.value
        model.stop()
    }

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

private actor SlowPresentationPermissions: PermissionAdapter {
    private let blockFirstMicrophone: Bool
    private var microphoneReads = 0
    private var microphoneContinuation: CheckedContinuation<Void, Never>?
    private var microphoneWaiters: [CheckedContinuation<Void, Never>] = []
    init(blockFirstMicrophone: Bool = false) { self.blockFirstMicrophone = blockFirstMicrophone }
    func waitUntilMicrophoneBlocked() async {
        if microphoneContinuation != nil { return }
        await withCheckedContinuation { microphoneWaiters.append($0) }
    }
    func releaseMicrophone() { microphoneContinuation?.resume(); microphoneContinuation = nil }
    private var continuation: CheckedContinuation<Void, Never>?
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private var released = false
    func status(_ kind: PermissionKind) async -> PermissionStatus {
        if kind == .microphone {
            microphoneReads += 1
            if blockFirstMicrophone, microphoneReads == 1 {
                await withCheckedContinuation {
                    microphoneContinuation = $0
                    microphoneWaiters.forEach { $0.resume() }; microphoneWaiters = []
                }
            }
        }
        if kind == .notifications, !released {
            await withCheckedContinuation { continuation = $0; waiters.forEach { $0.resume() }; waiters = [] }
        }
        return .granted
    }
    func waitUntilBlocked() async {
        if continuation != nil { return }
        await withCheckedContinuation { waiters.append($0) }
    }
    func release() { released = true; continuation?.resume(); continuation = nil }
    func request(_ kind: PermissionKind) async throws -> PermissionStatus { .granted }
    func openSettings() {}
}

private actor FailsFirstPlayback: PlaybackAdapter {
    private var failed = false
    private var value: PlaybackProjection?
    func play(noteID: NoteID, url: URL) throws -> PlaybackProjection {
        if !failed { failed = true; throw NSError(domain: "AudioPlayer", code: 1) }
        let next = PlaybackProjection(noteID: noteID, isPlaying: true, elapsedSeconds: 0, durationSeconds: 2)
        value = next; return next
    }
    func stop() { value = nil }
    func snapshot() -> PlaybackProjection? { value }
}

private final class RecoveryClaimGate: @unchecked Sendable {
    let entered: XCTestExpectation
    let cancelled: XCTestExpectation
    private let condition = NSCondition()
    private var released = false
    private var started = false
    init(entered: XCTestExpectation, cancelled: XCTestExpectation) { self.entered = entered; self.cancelled = cancelled }
    func wait() throws {
        condition.lock()
        defer { condition.unlock() }
        if started { return }
        started = true
        entered.fulfill()
        var reported = false
        while !released {
            if Task.isCancelled, !reported { cancelled.fulfill(); reported = true }
            _ = condition.wait(until: Date().addingTimeInterval(0.01))
        }
        try Task.checkCancellation()
    }
    func release() { condition.lock(); released = true; condition.broadcast(); condition.unlock() }
}
