import Foundation
import Observation
import WhimCore

/// Draft of every setting on the Settings screen, committed together by one Save action.
@MainActor @Observable public final class SettingsEditor {
    public let webhook: WebhookEditor
    public var retentionPolicy: RetentionPolicy
    public var transcriptionEnabled: Bool
    /// Shows the device language when no override is saved.
    public var language: String
    public let deviceLanguage: String
    public private(set) var preferencesError: IPhoneError?
    public var error: IPhoneError? { preferencesError ?? webhook.error }
    public private(set) var isPending = false
    private var saved: PreferenceInput
    private let client: any WhimClient

    public init(client: any WhimClient, preferences: PreferenceInput,
                deviceLanguage: String = Locale.current.identifier(.bcp47)) {
        self.client = client; self.deviceLanguage = deviceLanguage; saved = preferences
        webhook = WebhookEditor(client: client)
        retentionPolicy = preferences.retentionPolicy
        transcriptionEnabled = preferences.transcriptionEnabled
        language = preferences.transcriptionLocaleIdentifier ?? deviceLanguage
    }

    public var isDirty: Bool { webhook.isDirty || preferences != saved }
    public var canSave: Bool { isDirty && !isPending && !webhook.isPending }

    public func save() async {
        guard !isPending else { return }
        isPending = true; preferencesError = nil
        defer { isPending = false }
        if webhook.isDirty {
            await webhook.save()
            guard webhook.error == nil else { return }
        }
        let input = preferences
        guard input != saved else { return }
        do { try await client.updatePreferences(input); saved = input }
        catch is CancellationError {} catch { preferencesError = IPhoneError(error) }
    }

    /// Saving the device language keeps following the device instead of pinning it.
    private var preferences: PreferenceInput {
        let locale = language.trimmingCharacters(in: .whitespacesAndNewlines)
        return PreferenceInput(retentionPolicy: retentionPolicy, transcriptionEnabled: transcriptionEnabled,
            transcriptionLocaleIdentifier: locale.isEmpty || locale == deviceLanguage ? nil : locale)
    }
}
