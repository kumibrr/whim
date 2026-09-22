# Whim v1 privacy

Whim has no account, application backend, hosted audio storage, advertising, analytics, diagnostics upload, or telemetry. The iPhone and Watch store Notes and history locally. The configured webhook is chosen by the user; it receives the Note's audio, generated title, capture timestamp/duration, source device kind, workflow ID, app version/build, and immutable Note/Attempt IDs.

Paired-device synchronization can transfer audio, metadata, delivery state, and webhook configuration between the user's iPhone and Watch. Webhook secrets are stored in the platform Keychain. Local transcription uses on-device recognition and has no cloud-recognition fallback. A notification may contain a Note title and concise delivery failure reason; notification permission and Lock Screen preview visibility are controlled by system settings.

The selected Retention Policy removes local audio after successful delivery. Titles and delivery history remain until the Note is deleted or Reset is used. Unsent and unreviewed recordings are retained for recovery. Audio needed by an active workflow or an unacknowledged paired-device transfer remains until that work finishes. Reset removes local Notes, history, credentials, pending notifications, and scheduled work; a disconnected Watch reset remains pending until acknowledgement. Deleting or resetting in Whim cannot delete data already received by a webhook operator.

The self-hosted reference webhook has its own SQLite audio/metadata inbox. Its operator controls that database, downstream processing, backups, and retention. It is not an app service run by Whim.

## Release disclosure checks

The checked-in privacy manifest declares no tracking and no app-operator data collection. Required-reason API declarations must cover private and App Group preferences, elapsed-time measurement, and timestamps for owned files. The archive must contain the manifest in every app/extension that uses those APIs.

App Store disclosure answers must be reviewed against the actual release and endpoint arrangement before submission. Local-only processing is distinct from data sent to a user-selected webhook; this document does not assert that a remote endpoint's collection policies are controlled by Whim. Apple's [App Privacy Details](https://developer.apple.com/app-store/app-privacy-details/) explains collection disclosures, and its [required-reason API list](https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacyaccessedapitypes/nsprivacyaccessedapitype) defines the manifest reasons.

Physical notification-preview checks and the full acceptance matrix remain release gates; see [paired-device acceptance](../e2e/physical/paired-device.e2e.test.md).
