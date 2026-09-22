# Paired-device release acceptance

No physical case below has been executed for this change. Record the exact commit and devices for each run; simulator success is not physical sign-off. Use non-sensitive fixture speech and a controlled webhook. Save only redacted screenshots, timings, request counts, and pass/fail evidence under `evidence/`.

## Automated traceability

Paths below are relative to the repository root. Shared Swift companions are under `packages/WhimCore/Sources/WhimCore/`.

| Use case | Lowest deterministic coverage | Installed journey |
| --- | --- | --- |
| Permission outcomes and onboarding | `src/iphone/app-composition/IPhoneModel.integration.test.swift` | `e2e/iphone/onboarding.e2e.test.yaml` |
| Capture, Stop, Discard, interruption, duration limit | `Recording/RecordingService.integration.test.swift`, `Recording/PCMRecorderHardware.integration.test.swift` | `e2e/iphone/record-and-review.e2e.test.yaml`, `e2e/watch/WatchRecording.e2e.test.swift` |
| Recovery after termination and explicit Send | `Recovery/RecoveryScanner.integration.test.swift` | `e2e/iphone/recovered-review.e2e.test.yaml` |
| Playback, waveform, delete and playback failure | `Playback/AVAudioWaveformAdapter.integration.test.swift`, `AppComposition/WhimService.integration.test.swift` | `e2e/iphone/playback-error.e2e.test.yaml`, `e2e/watch/WatchNotes.e2e.test.swift` |
| Webhook validation, request bytes, credentials and configuration test | `WebhookConfiguration/WebhookRequestBuilder.integration.test.swift`, `WebhookConfiguration/KeychainCredentialStore.integration.test.swift`, `WebhookConfiguration/ConfigurationTestService.test.swift` | `e2e/iphone/settings-and-reset.e2e.test.yaml` |
| Offline capture, reconnect and bounded retries | `AppComposition/WhimService.integration.test.swift`, `Delivery/Delivery.test.swift` | `e2e/iphone/offline-and-retry.e2e.test.yaml` |
| Failure detail, retry and configuration change | `AppComposition/WhimService.integration.test.swift`, `src/iphone/webhook-configuration/WebhookEditor.integration.test.swift` | `e2e/iphone/failed-and-retry.e2e.test.yaml` |
| Retention, metadata preservation, reset, background deadlines and cancellation | `Maintenance/MaintenanceService.integration.test.swift`, `Maintenance/WatchBackgroundScheduler.test.swift`, `AppComposition/WhimService.integration.test.swift` | `e2e/iphone/retention.e2e.test.yaml`, `e2e/iphone/settings-and-reset.e2e.test.yaml` |
| App Shortcuts, repeated Record, Live Activity Stop | `src/intents/recording/RecordWhimIntent.test.swift`, `src/intents/recording/StopWhimRecordingIntent.test.swift`, `Recording/LiveActivityAdapter.test.swift` | `e2e/iphone/shortcuts-and-live-activity.e2e.test.yaml` |
| Cold links and Watch complication launch | `AppComposition/WhimService.integration.test.swift`, `src/watch/recording/WatchModel.integration.test.swift` | `e2e/iphone/cold-links.e2e.test.yaml`, `e2e/watch/ComplicationLaunch.e2e.test.swift` |
| Watch background/reentry and controls | `src/watch/recording/WatchModel.integration.test.swift` | `e2e/watch/WatchRecording.e2e.test.swift`, `e2e/watch/WhimWatch.e2e.test.swift` |
| Watch configuration, duplicate messages, ordering, receipts and tombstones | `DeviceSync/ConnectivityMergeService.integration.test.swift`, `DeviceSync/ReceivedPeerFileStore.integration.test.swift` | `e2e/iphone/watch-synchronization.e2e.test.yaml`, `e2e/cross-device/WatchSynchronization.e2e.test.swift` |
| Timeline filters and status presentation | `src/iphone/timeline/TimelineFormat.test.swift`, `src/iphone/app-composition/IPhoneModel.integration.test.swift` | `e2e/iphone/history-sheet.e2e.test.yaml` |
| Reference webhook signing, deduplication and restart | `packages/reference-webhook/src/note-created/receiveNote.integration.test.ts` | Physical duplicate-delivery row below |
| Privacy and Release fixture gates | `scripts/check-release-privacy.test.mjs`, `scripts/check-release-fixtures.test.mjs` | Built manifest verification in `scripts/verify-system-surfaces.py` |

The approved configuration-test asset is recorded in `docs/configuration-test-asset.md`. Physical sign-off remains pending.

## Physical matrix

Use [system entry procedures](iphone-system-entry-points.e2e.test.md), [Watch capture](watch-capture.e2e.test.md), [Watch synchronization](watch-synchronization.e2e.test.md), [presentation](iphone-presentation.e2e.test.md), and [background maintenance](background-maintenance.e2e.test.md) for detailed setup. Fill every evidence cell for the candidate build.

| Case | Build SHA | iPhone model/iOS | Watch model/watchOS | Preconditions | Exact actions | Expected result | Evidence path | Pass/fail | Tester | Date |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| App capture | — | — | — | Microphone granted | Launch each app, speak, Stop, play | One intelligible Note per device | — | Pending | — | — |
| Locked control | — | — | — | Configure Lock Screen control | Lock phone; Record twice; Stop in Live Activity | One continuing session; one Note | — | Pending | — | — |
| Action button | — | — | — | Supported phone; assigned shortcut | Lock phone; hold Action button; repeat Record; Stop | One session; no accidental toggle | — | Pending | — | — |
| Shortcuts and Siri | — | — | — | Shortcuts installed | Invoke Record and Stop via Shortcuts, then Siri | Each route controls the same recorder | — | Pending | — | — |
| Cold entry | — | — | — | App terminated | Invoke each configured system Record route | Recording starts or actionable permission guidance | — | Pending | — | — |
| Missing microphone permission | — | — | — | Deny microphone | Invoke control, shortcut and Action button | Permission guidance; no orphan capture | — | Pending | — | — |
| Live Activities unavailable | — | — | — | Disable Live Activities | Invoke locked system Record | No invisible intent-owned recording remains | — | Pending | — | — |
| Complication | — | — | — | Add Whim to active face | Tap complication; speak; Stop | New session visible; one saved Note | — | Pending | — | — |
| Locked and wrist-down duration | — | — | — | Microphone granted | Record for five minutes locked/wrist-down | Continuous intelligible audio; limit behavior correct | — | Pending | — | — |
| Live Activity and Dynamic Island | — | — | — | Supported phone | Record, lock, expand Island, Stop | Correct elapsed state; Stop finishes once | — | Pending | — | — |
| Smart Stack | — | — | — | Active Watch capture | Lower wrist; open Smart Stack; Stop | Capture state and Stop remain correct | — | Pending | — | — |
| Offline then online | — | — | — | Configured endpoint | Disable networking; capture; reconnect | Queued survives; one logical delivery | — | Pending | — | — |
| Simultaneous capture | — | — | — | Paired devices | Record both simultaneously; Stop both | Two distinct Note IDs; neither interrupts the other | — | Pending | — | — |
| Duplicate delivery | — | — | — | Deduplicating endpoint | Let Watch and iPhone send the same Note | Multiple Attempts; one stored logical Note | — | Pending | — | — |
| Transfer ordering | — | — | — | Controlled paired connectivity | Deliver file before state, then state before file | Same final Note/Receipt; no resend after Receipt | — | Pending | — | — |
| Offline configuration change | — | — | — | Watch disconnected | Change endpoint on phone; capture on Watch; reconnect | Revision sync and history remain truthful | — | Pending | — | — |
| Calls and Siri interruption | — | — | — | Recording active | Receive call; invoke Siri | Recoverable interrupted Note; truthful state | — | Pending | — | — |
| Audio route change | — | — | — | Bluetooth headset connected | Record; disconnect headset; Stop | No corrupt finalized audio; route feedback | — | Pending | — | — |
| Process termination | — | — | — | Recording active | Terminate app; relaunch | Recovered Note requires explicit review/Send | — | Pending | — | — |
| Storage pressure | — | — | — | Controlled near-full test device | Capture until write failure; relaunch | Actionable error; saved data remains recoverable | — | Pending | — | — |
| Failure notification | — | — | — | Notification granted | Exhaust retryable requests; reopen app | One notification with title/reason; failed row persists | — | Pending | — | — |
| Notification denial/previews | — | — | — | Denied or hidden previews | Cause failure; inspect locked screen and timeline | Timeline still highlights failure; system preview setting respected | — | Pending | — | — |
| Background expiry and Reset | — | — | — | Pending retry/retention | Follow background-maintenance procedure | Cleanup/retry resume; Reset invalidates work and notifications | — | Pending | — | — |
| VoiceOver/focus | — | — | — | VoiceOver enabled | Navigate capture, history, detail, settings | Labels and focus order permit complete journeys | — | Pending | — | — |
| Dynamic Type/contrast | — | — | — | Largest accessibility text | Inspect all screens and status colors | No clipped essential controls; distinguishable status | — | Pending | — | — |
| Haptics/Reduce Motion | — | — | — | Reduce Motion enabled | Start, Stop, Discard; navigate controls | Correct haptics; transitions avoid morph motion | — | Pending | — | — |
