# Whim Privacy Policy

Last updated: October 4, 2026. This policy covers Whim for iPhone and Apple Watch, version 1.

Whim records voice Notes, stores them on your devices, and delivers them to a webhook you choose. Whim does not require an account or operate an application backend or hosted audio-storage service. The app does not include advertising, tracking, analytics, diagnostics uploads, or usage telemetry. The developer does not receive your Notes through a Whim-operated service.

## Information stored on your devices

Whim stores audio recordings, Note titles, capture dates and durations, the source device kind, and delivery history locally. It also stores your preferences and webhook configuration. Delivery history includes identifiers for Notes and delivery Attempts, their status, and a destination with URL query values removed. Failed Attempts may retain a sanitized excerpt of the webhook's response to help you diagnose delivery problems.

Webhook credentials, including bearer tokens, signing secrets, and custom-header values marked secret, are stored in the platform Keychain. Configuration and credentials are used to authenticate delivery to your selected destination.

## Microphone and speech recognition

Whim requests microphone permission to capture audio when you start a Recording Session. Recording ends when you choose Stop or Discard, when an audio interruption ends it, or when it reaches the five-minute limit. You can revoke microphone permission in system Settings.

If you enable transcription and grant speech-recognition permission, Whim uses Apple's on-device speech recognition to generate a short Note title. It never falls back to server-based speech recognition and does not store the full transcript. If on-device recognition is unavailable or denied, Whim uses a timestamp title. Apple Watch Notes can receive an on-device title after reaching your iPhone. You can disable transcription in Whim's Settings or revoke speech-recognition permission in system Settings.

## Transfer between your iPhone and Apple Watch

Whim uses Apple's Watch Connectivity framework to synchronize your paired devices. Transfers can include audio, Note metadata, titles, delivery state, deletion and reset information, webhook configuration, and credentials. This lets your Watch record independently and lets both devices keep delivery status consistent.

## Delivery to your webhook

When you configure a webhook, finalized Notes are automatically sent directly to that destination when connectivity permits. Notes awaiting setup or a failed delivery may require you to choose Send or Retry. Recordings recovered after a crash require your review and an explicit Send action; they are not delivered automatically.

Your destination receives:

- The Note's audio and title.
- Capture date, duration, source device kind, title source, and whether capture completed normally, was interrupted, or was recovered.
- Note and Attempt identifiers, the Workflow identifier, and the app version and build number.
- Audio size and integrity hashes, request timestamps, and authentication or custom headers you configured.

The server also receives ordinary network connection information, such as the connecting IP address. The webhook operator controls whether it retains that information.

The Test webhook action sends a bundled, non-sensitive test recording and test metadata to your chosen destination. It does not create a Note in your local history.

Public webhook destinations require HTTPS with normal certificate validation. Whim also permits HTTP to supported private IPv4 destinations for local-network use. HTTP does not encrypt your audio or credentials in transit; use it only on a network you trust.

Your selected webhook may store audio, process it using other services, or create backups according to its operator's policies. Choose a destination you control or trust and review its data practices. The self-hosted reference receiver is operated by whoever installs it; it is not a Whim-operated service.

## Notifications

If you allow notifications, Whim can notify you of delivery failures. A notification may contain a Note title and a short failure reason. You control notification permission and Lock Screen previews in system Settings. Recording state and controls may also appear in Live Activities and on your paired Watch.

## Retention, deletion, and reset

Your Retention Policy determines when Whim removes local audio after successful delivery. Titles and delivery history remain until you delete the Note or reset Whim. Unsent Notes and recordings awaiting recovery review remain available until you delete them. Audio required by active work or a pending paired-device transfer is retained until that work finishes.

Deleting a Note removes its local audio and history and propagates deletion to your paired device when connectivity permits. Whim retains deletion coordination information until both devices acknowledge it, so an old copy does not restore a deleted Note.

Reset Whim removes local Notes, audio, history, preferences, webhook configuration, credentials, pending notifications, and scheduled work. Reset also requests removal on your paired device. A disconnected Apple Watch cannot be erased immediately; its reset remains pending until it reconnects and acknowledges the request.

Deleting a Note, changing its Retention Policy, or resetting Whim cannot revoke a delivery already accepted by your webhook or delete copies and backups held by its operator. To remove those copies, use your server's deletion tools or contact that operator.

## Your choices

You can record without configuring a webhook, change your destination in Whim's Settings, turn off transcription, change audio retention, delete individual Notes, or reset Whim. To remove saved delivery configuration and credentials, use Reset Whim. System Settings controls microphone, speech-recognition, notification, and Live Activity permissions. Revoking permission does not remove existing Notes or copies already delivered to a webhook.

## Questions

For privacy questions, email [onshore_pities.5s@icloud.com](mailto:onshore_pities.5s@icloud.com). For questions about information retained by your webhook, contact its operator.
