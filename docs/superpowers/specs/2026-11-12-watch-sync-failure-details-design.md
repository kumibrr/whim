# Watch synchronization failure details

**Date:** 2026-11-12

**Status:** Approved by the user on 2026-11-12

## Intent and selected approach

The user wants both Watch availability and Note Audio Synchronization failures to show a cause and recovery action, with expandable technical details.

Two presentation approaches were considered: plain-language guidance alone, or guidance plus expandable technical facts. The user selected the second. That requires capturing structured failure facts at their source: activation errors are currently discarded and audio synchronization records retry outcomes without causes. Rewording the existing generic statuses alone cannot provide reliable technical details.

Use the existing Watch Connectivity boundary, WhimClient projections, Note persistence, Settings screen, and Note details. Do not build a logging service or a separate diagnostics screen. This design implements the selected approach with additive, local metadata.

## User-visible behavior

### Settings → Apple Watch

- Keep the synchronization status and show a concise explanation and recovery instruction whenever unavailable. Keep the existing recording settings and reset feedback.
- Distinguish unsupported Watch Connectivity, an inactive connection, a recorded activation failure, no paired Watch, and iOS reporting Whim missing from Watch. Use a specific system cause only when it was actually reported. Unsupported is a known state; it must not be inferred from missing diagnostics.
- For unsupported devices, explain that Watch synchronization is unavailable on this device and that iPhone recording remains usable.
- For a connection that has not started, advise opening Whim on both devices and refreshing status. For an activation failure, explain the reported category when known; otherwise say iOS could not start the connection and advise closing/reopening Whim.
- For an unpaired Watch, direct the user to pair it using the iPhone Watch app. For a missing Watch app, direct them to check/complete installation in that app and open Whim on Watch. Do not recommend deleting/resetting Whim or removing its Watch app as first-line recovery.
- If the reason is unknown, say that Whim cannot determine the cause, give the basic open-both-apps/refresh guidance, and do not invent an error code.
- Add a **Refresh status** action using the existing presentation refresh operation. This reads current status; it is not a new forced reconnection or retry policy.
- Add a collapsed **Technical details** disclosure. Show supported status, activation state, pairing and installation state, immediate reachability, queued state/file transfer counts, and last successful synchronization when reported. Show an explicitly labelled latest activation/transfer error category, safe domain/code, and observed time when available. Missing facts read **Not reported**.
- Connection facts and errors are local to the current session. A successful activation clears the active activation failure. A historical transfer error must never override current availability or be presented as the cause of a different current problem.
- A paired, activated, installed Watch remains available while unreachable. Disconnection, queued preferences, and pending reset remain waiting states.

### Note details

- Keep **Sync failed** in the timeline status position and retain the existing **Retry sync** control. In Note details, show the known cause and a recovery instruction before the disclosure.
- Distinguish received audio that cannot be read as playable audio, a Watch source that cannot be supplied, and a local save failure when one is observed. A failed readability check does not prove permanent corruption; the wording must reflect what the app actually knows.
- When the Watch reports its source unavailable, optionally identify a missing Note/file, expired audio, unreadable audio, or a source not ready for handoff. Older peers that provide no reason use the general source-unavailable explanation.
- For unreadable received audio, explain that the iPhone could not read a playable copy and suggest opening Whim on Watch, checking playback there, and using Retry sync. For unavailable/expired source audio, explain that another copy may not be recoverable; do not promise Retry sync can restore a missing source. For local storage exhaustion, advise freeing iPhone storage before retrying.
- Waiting without a confirmed failure says the audio has not arrived; it must not claim corruption, missing Watch audio, or a network diagnosis.
- Add a collapsed **Technical details** disclosure containing Audio Synchronization state, transfer progress within the three-transfer cycle, last observed failure category/time, safe system domain/code when captured, Note/request identifiers, and the existing retry history. Label transfer progress separately from webhook Delivery Attempts. Preserve the original rule that the first transfer is not a retry-history row.
- Keep webhook Delivery details separate. A successful Receipt remains Sent even when audio synchronization fails, and a successful audio repair does not send an already delivered Note again.
- On manual retry, clear the active failure for the new cycle while retaining the previous retry's recorded cause in history. On successful repair, clear the active synchronization failure and retain the existing historical retry records.

## Data and boundary behavior

- Add optional status/technical-error fields to the existing Watch session/transport and Settings projections. Default implementations report unknown rather than fabricating system facts. The system adapter supplies actual WCSession fields.
- Capture activation completion errors and background-transfer completion errors as structured, sanitized values. Notify the existing presentation event stream when status/error facts change, including changes to unavailable pairing/installation states. Such notifications must not trigger destructive operations or gate recording on synchronization/recovery work.
- Retain only an allowlisted system error domain, numeric code, operation/category, and observed time. Do not store or display raw localized descriptions, userInfo, stack traces, URLs, file paths, credentials, Note titles, or audio in technical error metadata. Do not log or upload these details or send them to the webhook.
- Add optional cause information to the existing audio-unavailable response. Only the Watch's real store/file checks determine the cause; do not infer it on iPhone. Older peers continue to decode the additive message and may omit the cause.
- Add optional last-failure facts to persisted AudioSynchronization and optional cause/completion facts to retry-history records. Use the existing SQLite JSON fields; do not introduce a new database table or a free-form error log.
- Preserve failure details across store/service reconstruction. Legacy records and projections without these fields decode successfully. Unknown future cause values fall back to an unknown explanation without losing the Note or rejecting the whole projection.
- Record failure metadata only after the existing generation, deletion, request-identity, and duplicate guards accept the event. Associate each accepted response with its request. A stale/duplicate response cannot overwrite a newer failure or change retry history.
- Local save failures do not consume the corrupt/unavailable response budget. If recording diagnostics itself fails, preserve the original error and recoverable files; diagnostic failure must not mask the primary failure.
- Keep all existing retry accounting and handoff behavior: at most three transfers per cycle, waiting/offline time consumes none, no extra automatic cycles, and no acknowledgement of unreadable audio as durable. No changes to Delivery eligibility, Receipt precedence, deletion tombstones, retention holds, or recording startup priority.

## Verification

- Build vertical test-driven slices through the approved interfaces. Compose real adapter, merge/service, SQLite, file storage, and presentation models; fake only system boundaries.
- Cover safe system-error classification and absence of secret/path/message data. Cover status facts and failure propagation into WhimClient.settings(), including unsupported, activation failure, unknown/legacy, unavailable state changes, and recovery to available.
- Exercise the system WCSession delegate callback's capture/clear behavior in an iOS integration test and include that test in the existing native integration runner. Do not require pairing or real transfers for this deterministic callback regression.
- Feed real peer envelopes/files through merge/service and assert Note projections: unreadable input, unavailable sources with and without reason, local save failure, restart persistence, accepted/stale/duplicate replies, manual retry, valid repair, preserved retry history, unchanged counters, and absorbing Receipt success.
- Keep optional metadata decoding compatible with existing stored fixtures and older peers. Test unknown future reasons as well as absent fields.
- Use installed iPhone fixtures to cover cause/action text, expanding Technical details, known and unknown fields, and Retry sync followed by repair. Update existing retry-history assertions for the disclosure. Capture screenshots of the completed screens.
- Run affected suites and the root test:all with the shared advisory lock before completion. Physical acceptance covers actual pairing/installation reports, activation failures when reproducible, background transfer errors, VoiceOver, and Dynamic Type; deterministic tests do not claim physical sign-off.

## Builder choices

Type names, safe-domain representation, localization-ready presentation helpers, disclosure row layout, fixture names, and the injected clock plumbing are implementation choices. Reuse existing native components. Do not add a new public testing seam, new connection commands, telemetry, or a broad UI redesign.
