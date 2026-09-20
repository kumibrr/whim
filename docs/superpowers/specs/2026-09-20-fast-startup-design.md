# Fast startup on iPhone and Apple Watch

**Status:** Implemented. See [startup flow](../../startup-flow.md) for the resulting timeline and measurement limitations.

## Intent and success criteria

Show onboarding or the capture screen as early as possible, and make capture usable without waiting for history, audio validation, webhook credentials, pending Delivery, or Watch synchronization. Parallelize independent work while preserving recoverability and reset/deletion semantics. Keep iPhone tap-to-record, Watch first-activation auto-record, and existing permission behavior.

Success has two separate milestones: destination visible and capture ready. An early screen with an indefinitely disabled Record button is insufficient. Tests must demonstrate that deliberately suspended maintenance cannot prevent a new Recording Session from starting and stopping after essential initialization.

This specification changes startup scheduling and the WhimClient projection used to open the interface. It does not change Note/Delivery semantics or introduce analytics. The [startup trace](../../startup-flow.md) describes the implemented flow.

## Evidence and chosen approach

Current production composition awaits `WhimService.launch()`, which recovers peer state, scans audio, resumes eligible Notes, and queues the entire history for synchronization before returning the service. iPhone then reads all Notes, active recording, full settings, and playback sequentially before publishing its destination. Watch waits for full settings before auto-recording. Most service commands also use a shared command queue: merely wrapping these calls in parallel tasks would retain head-of-line blocking.

Choose staged readiness: lightweight routing, essential capture initialization, and deferred maintenance. Merely parallelizing current calls leaves the shared barrier intact. Moving the unmodified recovery scanner into a background task is unsafe because it enumerates Recording Sessions during execution and could recover a newly started session.

No elapsed-time improvement is claimed from source inspection. Record baseline and changed timings during implementation on the same simulator/device and data sets.

## Proposed timeline

| Stage | iPhone | Watch | Concurrent work |
| --- | --- | --- | --- |
| 1 | Read local onboarding flag; mount onboarding or capture shell. | Mount capture shell. | Start essential composition away from the main actor; read microphone status independently. |
| 2 | Reconcile authoritative capture state. | Reconcile authoritative capture state. | Open/migrate SQLite, prepare audio paths and recorder, resolve any pending reset, and establish the recovery inventory. |
| 3 | Enable Record when capture readiness and permission allow it. | First activation with permission starts capture; existing session is displayed. | Start maintenance and load auxiliary projections independently. |
| 4 | Recording event changes idle capture to the active recorder. | Show active recorder and start feedback. | Recover prior audio, load history/full settings, replay peer state, resume eligible Delivery, synchronize. |

The shell uses the actual local onboarding flag, not a guessed completed state. Its Record control shows a short preparing state until capture readiness; it never shows RECORDING before hardware startup succeeds. Watch does not display Allow microphone until permission status is known. Settings-dependent onboarding controls may load independently without withholding the introductory page.

## Readiness and presentation contract

Extend the existing WhimClient seam with a lightweight startup projection containing onboarding completion, microphone status, active Recording Session, and capture readiness/failure. It must not load Notes, webhook credentials, speech/notification permissions, or synchronization status. Expose readiness changes through the existing event stream, adding a typed event/projection as needed. These remain the agreed native presentation and WhimCore test seams.

Use the same onboarding store instance for the initial routing hint and canonical completion/reset updates. The hint is provisional: a recovered reset can route iPhone back to onboarding before capture is enabled. Presentation code must not independently write canonical state.

App entry points create presentation state immediately and retain one initialization task. Repeated appearances, scene activation, and Watch background callbacks join initialization rather than constructing duplicate services. Canceling a view task must not cancel service-owned recovery or an active Recording Session.

iPhone publishes startup state before history or full settings. History, full settings, and playback refresh independently, each with its own loading/error and stale-result protection. A failed history load cannot clear capture readiness. Subscribe before snapshots, preserve sequence-gap reconciliation, and prevent a late snapshot from overwriting a newer recording/reset event.

Watch auto-start remains once per model activation lifecycle, and only after microphone status and capture readiness are established. Scene reactivation refreshes state without auto-starting again after Stop. Permission grant through Allow microphone still starts capture immediately when ready. A single in-flight capture command prevents duplicate starts while activation and explicit actions overlap.

## Essential initialization and safe recovery

Essential initialization includes usable database/schema, audio paths, recorder construction, recording event observation, and a recovery boundary. Synchronous disk and adapter construction must not run on the main actor. Use bounded worker tasks; do not create an unbounded task per Note.

Before enabling a new Recording Session:

1. Inspect the durable reset state and pending reset messages. Complete any previously accepted destructive reset, including its canonical preference/onboarding effects. This exceptional path may delay capture because continuing erasure must not delete newly captured audio.
2. Establish an immutable recovery inventory of pre-existing Recording Session IDs, Note IDs/audio candidates, and deletion work. Inventory requires metadata/directory enumeration, not opening, decoding, hashing, or validating every audio file. Explicitly exclude any session owned by a live writer.
3. Publish capture readiness. All subsequent recovery work is restricted to that inventory. Never re-enumerate live sessions and treat newly created sessions as crash remnants.

The inventory can still grow with history size; its cost is measured separately. Full directory/database redesign is outside this change. Failure to establish a trustworthy inventory or finish a pending reset blocks recording with a retryable preparation error rather than risking audio loss.

Recovery must recheck tombstones and reset generation at commit time. It cannot recreate a deleted Note, publish a result from an obsolete generation, or rewrite a session started after inventory creation. Coordination must protect the actual mutation across suspension points; a generation check followed by an unprotected asynchronous write is insufficient.

Preserve existing writer-ownership guarantees and verify the live-writer exclusion through the recording/storage boundary. An active recorder in another same-device entry point must not be mistaken for a crash remnant. Where current code lacks a reliable ownership check, introduce process-safe ownership at that boundary before enabling concurrent recovery; timestamps or an in-memory set alone are not sufficient across processes.

Recovered playable audio remains a review-required Note. Invalid remnants remain visible local errors. Neither is automatically delivered. Stopping a new Recording Session must finalize it durably while old recovery remains suspended.

## Scheduling and command coordination

Separate essential readiness from maintenance completion inside WhimService. Capture commands and lightweight startup reads join only essential readiness. Existing `launch()` may remain an explicit await-all entry point for compatibility/tests, but production UI construction and capture must not call it implicitly.

Replace the universal command wait with scoped coordination. Serialize recording transitions with recording/reset operations; serialize conflicting Note changes by identity and generation. Independent reads and auxiliary settings/permission queries must not hold the capture command queue. Do not hold a global mutation lock while waiting for network, Keychain, audio validation, or an entire history scan.

Maintenance has explicit dependencies:

- Local recovery and non-destructive peer replay may operate concurrently only on disjoint identities. Conflicting mutations are coordinated per Note; reset invalidates the whole generation.
- An old Note becomes eligible for resumed Workflow only after its recovery/validation and relevant persisted peer state are reconciled. Previously received deletions or Receipts must take precedence over replaying an Attempt.
- Newly finalized Notes use the normal Workflow immediately; they do not wait for old history maintenance.
- Peer activation, full settings, and history presentation load independently. Activation callbacks cannot bypass the reset/identity coordination.
- Transfer submission, HTTP completion, and title completion never gate capture readiness.

Keep destructive reset globally coordinated: invalidate pending results, cancel and join conflicting workers, discard active capture according to existing reset semantics, then erase. User-initiated or newly received resets after startup use this same boundary. Delete prevents pending recovery of that Note from resurrecting it.

Lazy initialization is appropriate for configuration-test fixture loading and nonessential adapters. A missing test fixture should fail Test webhook, not ordinary capture. Preserve durable Workflow handoff when deferring service construction: no finalized Note may lose its required Delivery because auxiliary initialization is incomplete.

## Failure and lifecycle behavior

On both iPhone and Watch, startup and capture-related error states appear in a rounded Liquid Glass container in the upper half of the mounted screen, within its safe area. Each compact container includes a concise, human-readable explanation and a subtle chevron. The entire glass surface triggers the recovery action; there is no separate visible action button. VoiceOver announces the message and action hint. Do not expose raw exceptions or show a generic Retry action for a problem that requires changing permissions or configuration.

Use the existing appearance conventions: native Liquid Glass on iOS/watchOS 26+, a translucent material fallback on earlier supported versions, and an opaque, high-contrast background when Reduce Transparency is enabled. Error text and actions support Dynamic Type and VoiceOver. The container must not obscure Stop, Discard, elapsed time, or essential onboarding controls; reflow the upper content when necessary. Use content-sized wrapping text without a reserved scrolling region or action row. At large accessibility text sizes, grow the message naturally and keep capture controls reachable.

| Error | Message intent | Action |
| --- | --- | --- |
| Essential preparation failed | Explain that Whim could not prepare recording. | **Try again**, retrying only failed preparation. |
| Microphone denied or restricted | Explain why capture is unavailable and where access can be changed. | **Open Settings** when the platform adapter supports that route; otherwise **Show instructions**, opening device-specific guidance. Do not promise that a system restriction can be changed by Whim. |
| Storage full | Explain that more free storage is needed to save audio. | **Show instructions**, explaining how to free storage, with **Check again** in that guidance to retry preparation afterward. |
| History, settings, recovery, or synchronization failed | Name the affected operation and, when true, explain that recording remains available. | A specific retry label, such as **Retry history** or **Retry sync**. |
| Webhook configuration prevents Delivery | Explain that saved Notes need a working destination. | **Configure webhook** on iPhone; **Show instructions** on Watch, explaining how to configure it on iPhone. |

Show one error container at a time: capture-blocking errors take precedence over auxiliary failures. Retain other failures in model state and surface the next relevant one after resolution. Auxiliary errors may be dismissed by horizontal swipe or VoiceOver action; capture-blocking errors persist until resolved. Actions show in-flight feedback and reject duplicate taps. A failed action leaves a useful message and action available; successful resolution removes the corresponding error. Automatic state refresh also removes errors that have been resolved outside the app.

Do not publish capture ready after a failed critical step. Permission denial uses this same actionable container rather than a disconnected text-only warning. Unknown permission status remains a loading state, not an error.

History, settings, recovery, and synchronization errors are independently observable and retryable, without replacing the recorder. Keep unresolved old Notes ineligible for automatic Delivery. Retry is single-flight and idempotent; completed work is not blindly repeated. Service-owned tasks retain errors rather than silently swallowing them.

Background work means asynchronous service work during available execution time, not a promise of unlimited execution after iOS/watchOS suspension. Durable journals and recording recovery preserve unfinished work for the next opportunity. Watch Connectivity background task completion must continue to account for processing that the callback actually started.

## Verification

Build each behavior as a vertical test-driven slice, using real owned modules and controllable system adapters. Add failing companion tests before implementation.

| Seam | Required evidence |
| --- | --- |
| Native iPhone presentation | Hold history/full settings unfinished: destination and capture state still publish. Later failures do not remove the recorder. Onboarding routing and reset reconciliation remain correct. |
| Watch presentation | Hold history/Keychain/peer work unfinished: granted first activation starts exactly once. No transient permission request for already-granted access; reactivation after Stop stays idle. |
| WhimCore with real storage/files | Suspend old audio validation: a new session starts, stops, and becomes a durable Note. Release recovery: old audio becomes review-required and new audio remains unchanged. |
| Recording/storage boundary | A live writer is excluded from recovery; simultaneous startup callers share readiness and do not duplicate recovery/capture. Include same-device ownership coverage for separately composed clients. |
| Cross-device/reset boundary | Pending reset completes before capture; reset/delete during recovery prevents stale writes and resurrection. Receipt precedence survives replay. |
| Auxiliary services | Missing test fixture or delayed/failing credentials does not block capture; the relevant auxiliary operation reports its own error. |
| Error presentation | Correct message/action mapping, capture-blocking priority, independent retry state, and removal after resolution. Auxiliary failure cannot disable recording. |
| Installed apps | First-run onboarding, returning iPhone capture, Watch auto-capture, and Stop while maintenance is delayed. Keep assertions at the lowest sufficient suite. |

Add installed-app coverage for a preparation failure followed by successful retry and for microphone denial followed by the available settings/guidance action. Visually verify upper-half placement, glass/material/opaque appearances, readable contrast, and reachable controls on both device sizes, including large accessibility text. Never hide Watch startup errors exclusively on the Previous Notes page.

Use gates/continuations to prove non-dependency, with bounded test timeouts only as deadlock guards. Avoid pass/fail assertions based on arbitrary millisecond sleep thresholds.

Record local debug timing markers for app entry, first destination appearance, essential readiness, microphone started, and maintenance completion. Record no Note content or credentials and send no telemetry. Compare repeated cold/warm openings with empty and populated stores; report median and tail measurements and test conditions. Physical iPhone/Watch checks verify perceived speed, audio onset, wrist-down continuity, and no clipped initial speech. Do not claim a numeric speedup without measurement.

Run affected suites throughout implementation and `npm run test:all` before declaring completion. The last run failed during GRDB checkout due to disk exhaustion; recheck available space before builds and report any remaining environment limitation. Do not delete unrelated user data to make room.

## Scope and follow-through

Primary changes belong in app composition, WhimClient/WhimService, the two presentation models/root views, recovery, and peer/reset coordination, with adjacent tests. Update the startup trace to show the implemented sequence. No changes to webhook contract, onboarding steps, recording limits, or capture gesture semantics are intended.

Implementation is complete only when both early visibility and independent capture readiness are demonstrated, recovery/reset concurrency is covered, and required verification results are reported. A visual-only loading optimization does not meet this specification.
