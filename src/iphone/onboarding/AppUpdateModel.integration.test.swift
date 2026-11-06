import XCTest
import WhimCore
@testable import WhimIPhone

@MainActor final class AppUpdateModelIntegrationTests: XCTestCase {
    private let storage = UpdateDefaults()
    private var suite: String { storage.suite }
    private var defaults: UserDefaults { storage.value }

    func testFreshInstallNeverSeesItsAnnouncementAfterCompletingOnboardingOrRelaunching() async throws {
        let harness = try WhimFacadeHarness()
        defer { harness.remove() }
        let onboarding = UserDefaultsOnboardingStore(suiteName: suite)
        let client = harness.makeService(onboarding: onboarding)
        let update = AppUpdateModel(client: client, defaults: defaults)
        update.prepare(onboardingCompleted: onboarding.isComplete())
        XCTAssertNil(update.pendingUpdate)
        let interrupted = AppUpdateModel(client: client, defaults: defaults)
        interrupted.prepare(onboardingCompleted: onboarding.isComplete())
        try await client.completeOnboarding()
        interrupted.prepare(onboardingCompleted: onboarding.isComplete())
        XCTAssertNil(interrupted.pendingUpdate)
        let relaunched = AppUpdateModel(client: client, defaults: defaults)
        relaunched.prepare(onboardingCompleted: onboarding.isComplete())
        XCTAssertNil(relaunched.pendingUpdate)
    }

    func testExistingInstallWithNoMarkerSeesAnnouncementUntilExplicitAcknowledgement() throws {
        let harness = try WhimFacadeHarness()
        defer { harness.remove() }
        let client = harness.makeService()
        let update = AppUpdateModel(client: client, defaults: defaults)
        update.prepare(onboardingCompleted: true)
        XCTAssertEqual(update.pendingUpdate?.id, AppUpdate.current.id)
        let interrupted = AppUpdateModel(client: client, defaults: defaults)
        interrupted.prepare(onboardingCompleted: true)
        XCTAssertNotNil(interrupted.pendingUpdate)
        interrupted.skip()
        let relaunched = AppUpdateModel(client: client, defaults: defaults)
        relaunched.prepare(onboardingCompleted: true)
        XCTAssertNil(relaunched.pendingUpdate)
        let later = AppUpdate(id: "later-update", title: "Later", detail: "Another change", sections: [])
        let upgraded = AppUpdateModel(client: client, defaults: defaults, update: later)
        upgraded.prepare(onboardingCompleted: true)
        XCTAssertEqual(upgraded.pendingUpdate?.id, "later-update")
    }

    func testContinueSavesPreferenceDraftBeforePersistingAcknowledgement() async throws {
        let harness = try WhimFacadeHarness()
        defer { harness.remove() }
        let preferences = try UserDefaultsPreferenceStore(suiteName: suite)
        let client = harness.makeService(preferences: preferences)
        let update = AppUpdateModel(client: client, defaults: defaults, update: settingsUpdate)
        update.prepare(onboardingCompleted: true)
        await update.load()
        let editor = try XCTUnwrap(update.editor)
        editor.transcriptionEnabled = false
        editor.retentionPolicy = .never
        XCTAssertEqual(try preferences.load(), .default, "Editing must not change saved defaults")
        await update.complete()
        XCTAssertNil(update.pendingUpdate)
        let saved = try preferences.load()
        XCTAssertFalse(saved.transcriptionEnabled)
        XCTAssertEqual(saved.retentionPolicy, .never)
        let relaunched = AppUpdateModel(client: client, defaults: defaults, update: settingsUpdate)
        relaunched.prepare(onboardingCompleted: true)
        XCTAssertNil(relaunched.pendingUpdate)
    }

    func testSkipDiscardsPreferenceDraftWithoutChangingSavedSettings() async throws {
        let harness = try WhimFacadeHarness()
        defer { harness.remove() }
        let preferences = try UserDefaultsPreferenceStore(suiteName: suite)
        let update = AppUpdateModel(client: harness.makeService(preferences: preferences), defaults: defaults, update: settingsUpdate)
        update.prepare(onboardingCompleted: true)
        await update.load()
        let editor = try XCTUnwrap(update.editor)
        editor.retentionPolicy = .never
        update.skip()
        XCTAssertEqual(try preferences.load(), .default)
        XCTAssertNil(update.pendingUpdate)
    }

    func testContinuingDeferredAnnouncementPreservesNewerSettingsOutsideItsEditedControls() async throws {
        let harness = try WhimFacadeHarness()
        defer { harness.remove() }
        let preferences = try UserDefaultsPreferenceStore(suiteName: suite)
        let client = harness.makeService(preferences: preferences)
        let announcement = AppUpdate(id: "titles-update", title: "Titles", detail: "Choose title generation.", sections: [.onDeviceTitles])
        let update = AppUpdateModel(client: client, defaults: defaults, update: announcement)
        update.prepare(onboardingCompleted: true)
        await update.load()
        let editor = try XCTUnwrap(update.editor)
        editor.transcriptionEnabled = false
        // Settings can be opened by a deep link while an announcement is deferred.
        try await client.updatePreferences(.init(retentionPolicy: .never, transcriptionEnabled: true,
                                                transcriptionLocaleIdentifier: "fr-FR"))
        await update.load()
        await update.complete()
        let saved = try preferences.load()
        XCTAssertFalse(saved.transcriptionEnabled)
        XCTAssertEqual(saved.retentionPolicy, .never)
        XCTAssertEqual(saved.transcriptionLocaleIdentifier, "fr-FR")
    }

    func testFailedSaveKeepsAnnouncementAndDraftForRetry() async throws {
        let harness = try WhimFacadeHarness()
        defer { harness.remove() }
        let preferences = UpdateFailingPreferences()
        let client = harness.makeService(preferences: preferences)
        let update = AppUpdateModel(client: client, defaults: defaults, update: settingsUpdate)
        update.prepare(onboardingCompleted: true)
        await update.load()
        let editor = try XCTUnwrap(update.editor)
        editor.retentionPolicy = .never
        await update.complete()
        XCTAssertNotNil(update.pendingUpdate)
        XCTAssertNotNil(update.error)
        XCTAssertEqual(editor.retentionPolicy, .never)
        let relaunched = AppUpdateModel(client: client, defaults: defaults, update: settingsUpdate)
        relaunched.prepare(onboardingCompleted: true)
        XCTAssertNotNil(relaunched.pendingUpdate)
        await preferences.allowSave()
        await update.complete()
        XCTAssertNil(update.pendingUpdate)
    }

    func testResetDuringSaveCannotAcknowledgeOrReviveTheOldPresentation() async throws {
        let harness = try WhimFacadeHarness()
        defer { harness.remove() }
        let preferences = BlockingFacadePreferences()
        let update = AppUpdateModel(client: harness.makeService(preferences: preferences), defaults: defaults, update: settingsUpdate)
        update.prepare(onboardingCompleted: true)
        await update.load()
        let editor = try XCTUnwrap(update.editor)
        editor.retentionPolicy = .never
        let saving = Task { await update.complete() }
        await preferences.waitUntilSaving()
        update.prepare(onboardingCompleted: false)
        await preferences.finishSaving()
        await saving.value
        XCTAssertNil(update.pendingUpdate)
        XCTAssertNil(update.editor)
        update.prepare(onboardingCompleted: true)
        XCTAssertNil(update.pendingUpdate)
    }

    func testRootDefersAnnouncementDuringCaptureHistoryAndInactiveScenes() async throws {
        let harness = try WhimFacadeHarness()
        defer { harness.remove() }
        let client = harness.makeService(permissions: GrantedPermissions())
        try await client.completeOnboarding()
        let model = IPhoneModel(client: client, appUpdateDefaults: defaults)
        await model.start()
        defer { model.stop() }
        XCTAssertTrue(model.offersAppUpdate)
        model.openHistory()
        XCTAssertFalse(model.offersAppUpdate)
        await model.closeHistory()
        XCTAssertTrue(model.offersAppUpdate)
        await model.setSceneActive(false)
        XCTAssertFalse(model.offersAppUpdate)
        await model.setSceneActive(true)
        await model.startRecording()
        XCTAssertFalse(model.offersAppUpdate)
        XCTAssertNotNil(model.appUpdate.pendingUpdate, "Deferral must not acknowledge an announcement")
        await model.discardRecording()
        XCTAssertTrue(model.offersAppUpdate)
        await model.perform { try await client.reset() }
        XCTAssertFalse(model.offersAppUpdate)
        try await client.completeOnboarding()
        await model.refresh()
        XCTAssertFalse(model.offersAppUpdate)
    }

    private var settingsUpdate: AppUpdate {
        AppUpdate(id: "settings-update", title: "Your preferences", detail: "Choose your settings.",
                  sections: [.onDeviceTitles, .audioRetention])
    }
}

private final class UpdateDefaults {
    let suite = "app-update-\(UUID().uuidString)"
    let value: UserDefaults
    init() { value = UserDefaults(suiteName: suite)! }
    deinit { value.removePersistentDomain(forName: suite) }
}

private actor UpdateFailingPreferences: PreferenceStoring {
    var value = PreferenceInput.default
    var fails = true
    func load() -> PreferenceInput { value }
    func save(_ input: PreferenceInput) throws {
        if fails { throw CocoaError(.fileWriteNoPermission) }
        value = input
    }
    func reset() { value = .default }
    func allowSave() { fails = false }
}
