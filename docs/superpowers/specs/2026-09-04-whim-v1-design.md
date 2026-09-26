# Whim v1 Design

**Date:** 2026-09-04

**Status:** Approved

## Summary

Whim is a public power-user voice-note application for iPhone and Apple Watch. It minimizes the delay between intent and capture, keeps recordings recoverable offline, and delivers them directly to one user-configured webhook. Whim has no account, cloud storage, application backend, diagnostics, analytics, or telemetry in v1.

The iPhone interface uses SwiftUI (updated by the approved 2026-09-19 migration design). Native Swift owns recording and every behavior that must work from Apple Watch, App Intents, complications, Live Activities, or background execution without a running JavaScript runtime.

## Goals

- Start recording with the least practical delay from the iPhone app, iPhone Lock Screen recording control, Watch app, Watch complication, App Shortcut, Siri, and supported Action-button entry points.
- Record independently on iPhone and Apple Watch, including simultaneous recording on both devices.
- Preserve every finalized recording locally until the user deletes it or its successful-delivery retention period expires.
- Deliver recordings directly to a user-owned webhook through a documented, signed, idempotent contract.
- Remain useful offline and make queued or failed delivery state visible in the iPhone timeline.
- Generate short titles using only an on-device transcription model.
- Keep the v1 design small while retaining stable Workflow and Step identifiers for later evolution.

## Platforms and release boundary

- Minimum iPhone version: iOS 18.
- Minimum Watch version: watchOS 11.
- All iPhone, Watch, complication, Lock Screen recording control, iPhone Action-button, Live Activity, and Shortcut surfaces are required before v1 is complete, although implementation proceeds incrementally.
- Whim v1 is free and Apple-only.
- Android, web, macOS, and an optimized iPad interface are excluded.
- Both applications build natively in Xcode.

## Explicit non-goals

- Multiple user-configurable Workflows, a Workflow editor, or third-party Steps
- Pause/resume recording or the future Cut interaction
- Full transcript storage, title editing, trimming, tagging, sharing, or export
- An informational iPhone Home or Lock Screen widget; the recording control and Live Activity are required
- Accounts, cloud sync, a Whim-operated application backend, diagnostics, crash reporting, analytics, or usage telemetry
- StoreKit, subscriptions, or other monetization
- An application-specific biometric lock

## Architecture

Whim uses a native Xcode project committed under `ios/`. SwiftUI owns the iPhone presentation layer. A shared Swift package named `WhimCore` owns canonical state and native behavior.

```text
SwiftUI iPhone timeline and settings
                    │
             Native iPhone presentation model
                    │
App Intents ──── WhimCore ──── iPhone extensions
                    ⇅
             Watch Connectivity
                    ⇅
        SwiftUI Watch app + complication
```

`WhimCore` is used by the iPhone application, Watch application, App Intents, Live Activity, and WidgetKit extensions. Platform adapters provide microphone capture, filesystem access, Keychain access, notifications, HTTP transport, and Watch Connectivity.

The SwiftUI presentation model invokes the typed WhimClient interface and consumes projections and events. It never owns canonical Note, Delivery, or recording state. App Intents and extensions call `WhimCore` directly and never depend on starting JavaScript.

The initial native interface provides operations equivalent to:

```text
startRecording(source)
stopRecording()
discardRecording()
listNotes(filter)
retry(noteID)
delete(noteID)
updateWebhook(configuration)
testWebhook()
```

Complexity such as process coordination, state merging, retry scheduling, and secret access remains behind this interface.

## Domain model

The canonical terminology is also recorded in the repository's `CONTEXT.md`.

- A **Recording Session** is an active, unfinished audio capture.
- A finalized Recording Session becomes a **Note**, identified by an immutable random UUID.
- A **Workflow** describes post-capture behavior assigned to a Note.
- A **Step** is one named behavior in a Workflow.
- A **Delivery** is the logical requirement to submit one Note to its webhook.
- An **Attempt** is one HTTP request by one device. A Delivery may have multiple concurrent or sequential Attempts.
- A **Receipt** is evidence that an Attempt received a successful HTTP response.
- A **Configuration Revision** identifies the webhook configuration used by an Attempt without copying secrets into the Attempt.
- A **Retention Policy** defines when successfully delivered audio is removed locally.

V1 contains one built-in Workflow and two built-in Steps: on-device title enrichment and webhook delivery. Their stable identifiers are persisted. Neither depends on the other, so both may start after finalization without title generation delaying delivery. The persisted representation may include a `needs` array for future dependency-aware execution, but v1 does not implement a generalized plugin interface, output protocol, workflow editor, or third-party loading mechanism.

## Native persistence

`WhimCore` stores metadata and transactional state in SQLite. Audio is stored as protected `.m4a` files outside the database, named by Note ID. Credentials and secret custom-header values are stored only in Keychain.

Recording first creates a database Recording Session and temporary file. Successful finalization atomically moves the audio into its durable Note location and records the Note and Delivery transactionally. A database record must never claim finalized audio exists before the file is durable.

Same-device workers use transactional leases so separate processes do not accidentally perform the same work. Cross-device Watch and iPhone Attempts may deliberately race.

Active and unsent files use data protection compatible with Lock Screen capture after the device's first unlock. Delivered files move to stricter protection. Metadata does not contain webhook secrets, full transcripts, or audio content.

## Recording behavior

### iPhone

1. An invocation asks `WhimCore` to create a Recording Session and temporary audio file.
2. Whim starts the required Live Activity and activates a native recording session.
3. When supported and authorized, on-device transcription starts concurrently.
4. Stop finalizes AAC-LC mono audio in an `.m4a` container, creates the Note and Delivery, ends the Live Activity, and starts both v1 Steps.
5. Webhook delivery begins without waiting for the title.
6. The title updates locally when transcription finishes.

Recordings use a speech-oriented bitrate. The maximum duration is five minutes and is defined in one internal configuration location so a future release can change it without rewriting recording behavior. Whim warns shortly before the limit and stops safely at the limit.

There is no pause action. Stop saves and sends; Discard immediately destroys the current Recording Session without confirmation. Its button is red with an enlarged tap target. On iOS 26 and watchOS 26 or later, its glass capsule morphs from the Record/Stop control; Reduce Motion disables the morph. Invoking Record while the same device is already recording focuses the active recorder instead of toggling or starting another session.

Audio interruptions stop and safely finalize playable audio as an interrupted Note, which follows normal automatic delivery. Whim never resumes microphone capture without a new user action.

A recording shorter than one second with no meaningful audio is automatically discarded. Any longer playable recording is preserved.

### Crash recovery

On launch, Whim examines unfinished Recording Sessions. A playable partial file becomes a recovered Note titled "Recovered recording." The user must review it and explicitly choose Send or Delete. It is never delivered automatically. An unreadable remnant remains represented as a visible local error until the user deletes it.

### Apple Watch

The Watch records through its own microphone and maintains its own local store. At finalization it immediately starts a direct webhook Attempt when it has usable configuration and also queues the audio and metadata for background transfer to iPhone.

The Watch and iPhone are both allowed to attempt delivery with the same Note ID. A Receipt is an absorbing success state: later failures, stale messages, crashes, or timeouts cannot regress a delivered Note.

The iPhone imports Watch files and state idempotently in either arrival order, generates a title locally, and synchronizes the resulting title and status to Watch. Watch itself does not perform transcription in v1. It uses a timestamp title for any direct webhook delivery.

Watch recording continues through wrist-down until Stop, an audio interruption, or the five-minute limit. This behavior is a release-blocking physical-device acceptance criterion.

## Cross-device configuration and state

Webhook configuration moves from iPhone to Watch using Watch Connectivity and is stored in the Watch Keychain. Configuration editing exists only on iPhone. Watch shows availability and last synchronization status but never renders secrets.

Each device uses the newest Configuration Revision it knows. An offline Watch may deliver using an older revision. If that Attempt fails, iPhone retries the Note with its current configuration after synchronization. A successful response from an older endpoint still creates a permanent Receipt.

Each Attempt records its Configuration Revision and sanitized endpoint: scheme, host, port, and path without query values. Advanced Note details may display that destination for diagnosis.

Deletion propagates by Note ID. Tombstones remain until both paired endpoints acknowledge them so a stale offline copy cannot resurrect. Deletion never sends a corresponding request to the user's webhook. Reset requests synchronize after reconnection but cannot erase a disconnected Watch immediately.

## Title enrichment

Whim uses Apple's speech recognition only when it reports on-device support and sets recognition to require on-device processing. It never falls back to server transcription.

The first meaningful sentence, truncated to approximately 60 characters, becomes the title. Whim retains only the title and discards the full transcript. If transcription is unavailable, denied, empty, or delayed, Whim uses a localized timestamp title. Delivery waits no more than 300 milliseconds for a final title and otherwise proceeds with the fallback. A later local title update does not cause another webhook request.

The default recognition language follows the device language. Settings provides an explicit language override. Watch recordings are transcribed after reaching iPhone.

## Webhook configuration

V1 supports one active webhook configuration containing:

- One HTTPS URL using normal certificate validation
- Optional bearer token
- Optional HMAC secret
- Up to ten custom headers

Whim rejects redirects and reserved-header overrides. Secret values are masked in the interface and stored in Keychain. Updating configuration applies the newest values to all unsent Notes. Attempts retain the revision and sanitized destination they used, not secret snapshots.

Saving configuration does not by itself prove it works. Passing the bundled test offers to retry failed Notes and send Notes awaiting setup.

## Webhook request contract

Whim sends a fixed HTTPS `POST` using `multipart/form-data`:

- `metadata`: UTF-8 JSON with media type `application/json`
- `audio`: the `.m4a` file with media type `audio/mp4`

The metadata schema is versioned from its first release:

```json
{
  "schema_version": 1,
  "event": "note.created",
  "note_id": "immutable UUID",
  "attempt_id": "UUID",
  "created_at": "ISO-8601 UTC timestamp",
  "duration_ms": 42000,
  "source": "iphone",
  "title": "Idea for the onboarding flow",
  "title_source": "transcription",
  "capture_outcome": "completed",
  "workflow_id": "default",
  "audio": {
    "sha256": "lowercase hexadecimal digest",
    "size_bytes": 338112
  },
  "app": {
    "version": "1.0.0",
    "build": "1"
  }
}
```

`source` is `iphone` or `apple_watch`. `title_source` is `transcription`, `timestamp`, or `recovered`. `capture_outcome` is `completed`, `interrupted`, or `recovered`.

Requests include:

```text
X-Whim-Note-ID: <note UUID>
X-Whim-Attempt-ID: <attempt UUID>
X-Whim-Timestamp: <Unix timestamp in seconds>
X-Whim-Metadata-SHA256: <digest of exact metadata part bytes>
X-Whim-Audio-SHA256: <digest of exact audio bytes>
Authorization: Bearer <optional token>
```

The `Authorization` header is omitted when no bearer token is configured. When an HMAC secret exists, Whim also sends `X-Whim-Signature: v1=<lowercase hexadecimal HMAC-SHA256>`. Its signed UTF-8 input is newline-delimited in this exact order:

```text
v1
<timestamp>
<note_id>
<attempt_id>
<metadata_sha256>
<audio_sha256>
```

The server must deduplicate logical Notes using `X-Whim-Note-ID`. Attempt IDs distinguish transport attempts but are not idempotency keys.

Any `2xx` response creates a Receipt. Redirects fail. Network errors, `408`, `425`, `429`, and `5xx` are retryable. Other `4xx` responses become failed immediately because repeating the same request cannot repair them. `429 Retry-After` is honored without exceeding the Attempt limit. Request and resource timeouts are bounded for the largest supported audio file.

Whim retains the response status and a small, capped error-response excerpt locally in the Attempt. It never logs request headers, response bodies, Note titles, or audio.

### Configuration test

A prerecorded, non-sensitive clip supplied by the product owner ships as an application asset. The test uses the production contract with a fresh Note and Attempt ID and `event: "configuration.test"`. It does not appear in Note history or consume Note retry state.

A `2xx` response passes. Whim also looks for the same Note ID in either an `X-Whim-Note-ID` response header or a JSON `note_id` field. If absent, setup warns that server-side idempotency could not be confirmed without turning a successful response into a failure.

## Delivery states and retries

The iPhone interface projects internal state into these statuses:

- **Setup required**: no usable webhook configuration exists.
- **Queued**: delivery is eligible but currently offline or waiting for execution.
- **Sending**: at least one local Attempt is active.
- **Sent**: any device has a Receipt.
- **Failed**: a permanent error occurred or retryable Attempts are exhausted.

Being offline does not consume an Attempt. Once online, retryable work attempts immediately, then becomes eligible after one minute and fifteen minutes. These are earliest eligible times because operating systems do not guarantee exact background scheduling. After three actual failures, automatic retries stop and Whim generates one local notification. It does not retry continuously.

Users can retry one Note or all failed Notes. Saving valid configuration or passing its test offers the same action. Already delivered Notes never resend.

Failure notifications include the generated title and concise reason. The user controls whether notification previews appear on the Lock Screen through system settings. If notification permission is denied, the failed Note remains highlighted in the timeline.

## Retention and deletion

Retention is measured from successful delivery, never recording time. Options are Immediately, 1 day, 7 days, 30 days, 90 days, and Never. The default is 30 days.

Expiration deletes audio but retains lightweight timeline metadata: title, time, duration, source, and delivery result. Queued, failed, setup-required, and recovered Notes are never removed automatically.

Deleting delivered Notes is immediate. Deleting queued, sending, failed, or recovered Notes requires confirmation because it may destroy the only copy. A local delete cannot revoke a request already accepted by the user's server.

## iPhone experience

Whim opens to a recording-first black home screen, as updated by the approved [2026-09-19 iPhone design](2026-09-19-iphone-recording-first-design.md). A plain white line sits in the center, with a glass Record button at bottom center and an icon-only glass settings button at top right. The hint “scroll to see previous notes.” opens history by upward drag or tap. History uses a native sheet with its own navigation toolbar and provides one soft haptic when opening commits.

History contains newest-first glass Note cards with a single-line title and date/time on the left, an inline waveform player alongside, and duration, source device, and delivery/review status. Accessibility text sizes stack the layout and allow title wrapping. Failed Notes remain in chronological position with prominent text and symbol treatment plus a Retry action. Filters offer All, Queued, Failed, and Sent. Only one Note plays at a time; leaving history or opening detail stops inline playback.

Record starts capture immediately. The full-width central line reacts to microphone input without progressively filling the screen. During a Recording Session, only Stop and immediate Discard are available; history and settings are inaccessible. Elapsed time, five-minute progress, and the limit warning remain visible. Stop returns to idle without opening history. Visible and haptic feedback confirm start and stop.

Note detail offers playback, delivery details, Retry when applicable, and Delete. Recovered Notes instead offer Review, Send, and Delete.

Settings includes webhook configuration and test, a webhook error log listing each failed Attempt’s status and retained response excerpt newest first, retention period, transcription enablement and language, notification status, Watch synchronization status, and Reset Whim. Reset requires destructive confirmation and removes local audio, metadata, history, configuration, and credentials.

Onboarding:

1. Explain local storage and direct webhook delivery.
2. Offer webhook configuration and test, with Skip available.
3. Request microphone permission.

Speech and notification permissions are requested contextually after the first recording. Denied permissions are not repeatedly requested; Settings provides the relevant system-settings route.

The iPhone uses a sober black appearance with white accents and native typography, native Liquid Glass where available, and a translucent material fallback on iOS 18. Watch appearance remains unchanged apart from sharing the iPhone's logo waveform on its capture screen. Every status includes text or symbols rather than relying on color. VoiceOver, Dynamic Type, sufficient contrast, haptic plus visible feedback, logical focus order, and Reduce Motion support are v1 requirements.

## Watch experience

After microphone permission exists, launching Whim through the app icon, complication, App Shortcut, or supported Action-button route starts recording immediately. The primary view shows elapsed time, Stop, and Discard. A secondary recent-Notes view exposes locally available playback, delivery status, Retry, and Delete.

Watch produces a distinct start haptic, restores the active recorder after wrist-down, and stops safely at five minutes. Configuration may be viewed only as available/unavailable and last synchronized.

The WidgetKit complication shows the Whim mark while idle, elapsed recording state while active, and an attention indicator when failed Notes exist. Tapping it launches directly into capture.

## App Intents, Lock Screen control, Action button, and Live Activity

Whim defines separate "Record a Whim" and "Stop Whim Recording" App Shortcuts. The recording intent conforms to `AudioRecordingIntent`; starting it creates and maintains the required Live Activity for the full recording. A second Record invocation focuses the active recorder rather than toggling state.

On iPhone, the Live Activity displays elapsed time and Stop on the Lock Screen and Dynamic Island. The activity appears in the paired Watch Smart Stack where supported. Missing permission routes into Whim with an explanation instead of silently failing.

On iOS 18 and later, Whim provides a “Record a Whim” WidgetKit control that the user can add to the Lock Screen. It invokes the same recording intent to start capture while the iPhone remains locked, after microphone permission has been granted. It is available before a Recording Session exists; the Live Activity supplies elapsed time and Stop after capture starts.

On supported iPhones, the user can assign the “Record a Whim” App Shortcut to the Action button in system Settings. Activating it starts capture while locked or unlocked. Repeated Lock Screen or Action-button invocation preserves the existing Recording Session and never toggles it off. Both routes use the same local recorder and required Live Activity lifecycle as other intent entry points. Missing permission routes into Whim with an explanation; any required system authentication is respected. Locked recording is a physical-device acceptance requirement, not satisfied by merely opening the app.

No informational iPhone widget ships in v1. The recording control is the explicit exception to the previous exclusion of separate iPhone widgets.

## Error handling

- Missing microphone access prevents capture and offers a route to system settings.
- Audio-session activation failure creates no empty Note.
- Audio interruptions finalize playable content as an interrupted Note.
- Disk-full and corrupt-file states remain visible and are never represented as delivered.
- Transcription failure uses the timestamp title and never blocks delivery.
- Background-task expiration first persists recoverable state.
- Watch imports, status messages, receipts, and deletions are idempotent and may arrive in any order.
- A Receipt always takes precedence over failure or in-progress state.
- Reset propagates to a paired device when connectivity permits.

## Verification strategy

### Test-driven development policy

Every production behavior change is implemented as a vertical test-driven slice:

1. Name the user or caller use case and the public seam where its result is observable.
2. Add or update one companion test and run it to observe the expected failure.
3. Add the minimum implementation that satisfies that test.
4. Run the affected suite and every previously passing test at that seam.
5. Run all three suites before the change is considered complete.

Bug fixes begin with a regression test that reproduces the reported behavior. Documentation-only and non-behavioral repository maintenance do not require artificial tests.

A change does not need to repeat the same assertion in all three suites. Coverage belongs at the lowest seam that proves the behavior, while a changed end-user journey requires corresponding E2E coverage. Tests verify observable behavior through interfaces rather than private implementation details. Mocks and fakes are limited to system boundaries such as time, microphone hardware, networking, notifications, and Watch Connectivity; owned modules run together in integration tests.

The repository exposes stable root task-runner scripts throughout development:

```text
test:unit
test:integration
test:e2e:iphone
test:e2e:watch
test:e2e
test:all
```

`test:e2e` aggregates the iPhone and Watch E2E suites. `test:all` runs unit, integration, and E2E suites. Target-specific scripts may exist, but these aggregate entry points remain stable.

### Agreed test seams

Tests exercise these public seams:

1. **WhimCore interface:** recording transitions, Note queries, Send, Retry, Delete, configuration, and test delivery.
2. **Platform adapter interfaces:** microphone, clock, filesystem, Keychain, notification, HTTP, and Watch Connectivity behavior supplied to WhimCore.
3. **Cross-device protocol:** versioned Watch/iPhone messages and their idempotent merge results.
4. **Native iPhone presentation interface:** typed commands, observable projections, and native events.
5. **Webhook boundary:** the complete HTTP request observed by a real loopback receiver and the resulting Delivery state observed through WhimCore.
6. **User interface:** accessibility-visible iPhone and Watch behavior.
7. **Installed application:** complete journeys through compiled development builds.

New test seams require an explicit design decision. Tests may use internal helpers for fixture setup, but assertions remain against these interfaces.

### Unit suite

The unit suite is deterministic, has no network or simulator dependency, and is suitable for continuous watch mode. Swift tests exercise domain rules through focused module interfaces. The root Swift package covers iPhone formatting and presentation rules. Accessibility-visible UI behavior is exercised through the installed native app.

Unit cases include:

- Recording and recovery state transitions
- Delivery transitions and permanent Receipt precedence
- Concurrent Watch/iPhone Attempt merging by Note ID
- Retry classification, scheduling, and Attempt limits
- Configuration revision selection
- Tombstone and retention rules
- Webhook metadata, canonical signing input, hashes, and secret redaction
- Timeline projections, filters, status labels, and settings validation

Tests involving real SQLite, files, or HTTP belong to integration rather than unit scope.

### Integration suite

Integration tests compose owned modules through their public interfaces using an isolated temporary SQLite database and filesystem. A deterministic local webhook receiver produces success, timeouts, connection loss, delayed responses, duplicate requests, every relevant HTTP status, invalid signatures, and oversized error responses.

Integration coverage includes:

- Recording finalization across the store and filesystem using fixture audio
- Process termination followed by recovery from persisted state
- Complete multipart bodies, headers, hashes, HMAC signatures, and response classification
- Retry scheduling with an injected clock and network state
- Concurrent Watch/iPhone messages delivered in every meaningful order
- Configuration synchronization and last-known Watch configuration
- Deletion tombstones and retention across simulated restarts
- Native iPhone presentation commands, projections, event ordering, and lifecycle
- Presentation models composed with real WhimService and isolated persistence

The suite verifies results through WhimCore, the native presentation interface, or the loopback receiver. It does not query internal tables merely to prove behavior.

### End-to-end suite

The E2E suite drives compiled development builds as a user would. Maestro covers iPhone journeys. A watchOS UI Testing Bundle using XCTest and XCUIAutomation covers Watch journeys. E2E builds accept a debug-only launch argument that feeds deterministic fixture audio through the real recording workflow; release builds do not contain that switch. Real microphone and background behavior remain part of physical acceptance.

Required iPhone E2E journeys include:

- Complete or skip onboarding and handle each permission outcome
- Start, stop, discard, play, and delete a Note
- Configure and test a webhook against the local receiver
- Record offline, observe Queued, reconnect, and observe Sent
- Observe a failed row, inspect its reason, update configuration, and retry
- Review and explicitly send a recovered Note
- Change retention and reset all local data
- Start through the Lock Screen recording control and App Shortcuts, and stop through the Live Activity where simulator automation permits; cover the shared Action-button intent through the same automated seam

Required Watch E2E journeys include:

- Start from app launch and complication launch context
- Stop, discard, play, retry, and delete
- Preserve the active recorder across simulated wrist-down and background transitions
- Queue without configuration and reflect configuration synchronization
- Race direct delivery with iPhone handoff using one Note ID
- Merge file, failure, and Receipt messages in alternate arrival orders

The E2E runner starts and resets its own webhook fixture, installs clean builds, uses isolated data per test, and captures screenshots and logs only on failure. Each test is independently rerunnable.

Swift XCTest covers native domain and presentation tests; Maestro covers compiled iPhone journeys and XCTest covers Watch journeys.

### Continuous integration

Every pull request runs unit, integration, iPhone E2E, and Watch E2E suites. A failure in any required suite blocks merge. Linux jobs run Node tooling and webhook-fixture checks, while macOS jobs build native targets and run Swift, simulator, and E2E suites. iPhone Maestro and Watch UI tests run on macOS CI.

### Physical-device acceptance suite

A paired physical iPhone and Apple Watch must verify:

- Capture from the app, iPhone Lock Screen recording control, complication, App Shortcut, Siri, and supported Action-button entry points
- On a supported physical iPhone, configure the Lock Screen control and Action-button shortcut; start from each while locked, repeat Record without creating another session or stopping, and stop through the Live Activity
- Repeat both iPhone routes with the app not running, with microphone permission missing, and with Live Activities unavailable; verify permission guidance and that activity-start failure leaves no intent-owned capture running
- Locked-iPhone, wrist-down Watch, and five-minute recording
- Live Activity, Dynamic Island, Smart Stack, and Stop intent
- Offline capture and later delivery
- Simultaneous iPhone and Watch recording
- Concurrent duplicate HTTP requests with server idempotency
- Watch file and status arrival in either order
- Configuration changes while Watch is disconnected
- Calls, Siri, route changes, termination, and storage pressure
- Local notifications and Lock Screen preview settings
- VoiceOver, Dynamic Type, contrast, haptics, focus order, and Reduce Motion

These cases are versioned beside the automated E2E suite as executable test procedures with expected evidence. Signing, App Intents, complications, Watch background recording, Watch Connectivity file transfer, and cross-device races require this real-device verification before release.

## Release completion criteria

V1 is complete only when:

- Unit, integration, iPhone E2E, and Watch E2E suites pass in CI through the stable root commands.
- Every implemented use case has companion automated coverage at an agreed seam; changed user journeys have companion E2E coverage.
- Every iPhone and Watch target builds from a clean checkout.
- The full physical-device acceptance matrix passes.
- A reference webhook verifies signatures and deduplicates concurrent Attempts by Note ID.
- App privacy disclosures match the implemented behavior: audio and titles go only to the configured user endpoint; Whim sends no diagnostics or telemetry elsewhere.
- The product-owner-provided configuration-test audio asset is present and non-sensitive.
