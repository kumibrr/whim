# Paired Watch synchronization acceptance

Status: **Not run — physical iPhone and Apple Watch required.** Simulator PeerTransport
journeys prove protocol/composition behavior only. Apple does not support
`WCSession.transferFile` on Watch Simulator.

## Setup and evidence

Install the same Release build on paired iPhone (iOS 18+) and Watch (watchOS 11+).
Use a user-owned HTTPS receiver that records Note ID, Attempt ID, sanitized endpoint,
status and request count, and deduplicates Note IDs. Keep credentials and audio out
of test transcripts. Record device/OS/build, observed timeline/status, receiver
counts and screenshots for each case. Do not enable DEBUG fixture switches.

## Cases

1. **Background file handoff:** record on Watch with its direct networking disabled,
   stop, background both apps, restore connectivity. iPhone imports playable audio
   with the same Note ID, enriches its title and delivers. Watch receives Sent and
   the title without foreground interaction. Repeat with state before file and file
   before state by controlling device connectivity; confirm one Note per ID.
   While the system holds userInfo and audio-file transfers, trigger repeated
   activation/reachability changes and relaunch the sender. Record outstanding
   transfer counts: replay must not add copies of the same message ID, including
   transfers queued but not yet scheduled by WCSession. Once a held transfer
   completes or is canceled, an unacknowledged replay may enqueue it again.
   Deterministic adapter tests cover suppression and release with a fake system
   queue; WCSession persistence, scheduling and completion require these devices.
2. **Direct race:** configure both devices, record on Watch, stop while both can reach
   the receiver. Observe distinct Watch and iPhone Attempt IDs for the same Note ID.
   The receiver creates one logical Note. Return success to one and failure/timeout
   to the other in both orders. Both devices remain Sent after relaunch. A late
   title never sends another request. Repeat with two successful responses; both
   stores use the earliest Receipt time for retention.
3. **Disconnected configuration:** disconnect Watch, change endpoint and secrets on
   iPhone, record on Watch at its old endpoint. An old success remains Sent after
   reconnection. An old failure allows iPhone delivery at its newest endpoint.
   Reconnect and verify Watch configuration availability and last synchronization.
   Neither UI nor persisted nonsecret metadata exposes credentials or URL query values.
4. **Deletion and reset:** disconnect peer, delete an unsent Note or reset iPhone.
   Confirm pending reset feedback and that disconnected Watch is not falsely shown
   erased. Reconnect, confirm removal on both devices and completed reset feedback.
   Relaunch both and replay delayed old file/state transfers; no erased Note returns.
   Record after completed reset and deliver a duplicate reset; new recording remains.
5. **Background lifecycle:** deliver multiple queued state/files while Watch is in the
   background. Confirm every Watch Connectivity refresh task completes once only
   after activation, pending content drains and local imports finish. Kill/relaunch
   between system file receipt and import; owned audio is recoverable and imported.
6. **Destructive actions during race:** while a local Retry/peer-import HTTP request
   is stalled, start/stop another recording, then Delete or Reset. Capture stays
   responsive; local work is canceled/joined and late peer messages cannot resurrect
   data. A request already accepted by the receiver cannot be revoked.
7. **Interrupted handoff recovery:** record on Watch while iPhone changes between
   Wi-Fi and cellular, then terminate iPhone during background handoff. Relaunch
   iPhone and record another Note on Watch. Background recovery must finish and the
   new Note must arrive, play and deliver without Reset Whim. If Watch resends the
   interrupted Note, confirm playable audio and a single logical Note at the
   receiver after another relaunch. Delete the interrupted Note on Watch while
   disconnected, reconnect, and confirm delayed transfers cannot resurrect it.
   Repeat while iPhone is locked after first unlock. A simulator fixture covers
   persisted truncated pending audio, recovery, resend and Delivery;
   real suspension timing and Watch Connectivity still require these devices.
   Confirm iPhone shows the Note while waiting for its audio, disables playback,
   and leaves any Watch Receipt Sent. For reproducible corruption, confirm the
   first transfer plus at most two automatic resends precede Sync failed; time
   spent disconnected does not consume transfers. Retry sync starts a fresh
   three-transfer cycle. Delete a pending Note on iPhone with confirmation and
   reconnect Watch: it disappears on both devices and delayed audio stays deleted.

8. **Settings availability explanation:** on a test iPhone without a paired Watch,
   open Settings → Apple Watch and confirm the explanation says no Watch is paired.
   On a paired test device without the Watch app installed, confirm Settings explains
   that iOS reports Whim missing and offers installation from the iPhone Watch app.
   Install Whim and activate both apps; reopen Settings and confirm synchronization
   is available and the explanation disappears. Disconnect the installed, activated
   Watch without unpairing or uninstalling it; it must remain available even when
   unreachable. If an inactive session is observed, confirm the reopen guidance.
   Record screenshots and VoiceOver output. Automated coverage uses a fake system
   session through the real adapter/service and `watch-unavailability.e2e.test.yaml`;
   actual pairing, installation reporting, and activation require these devices.

All eight cases block release until evidence is recorded. Simulator passes do not
satisfy real transferFile, locked-device background execution, or paired race acceptance.

## Cause, recovery and technical details acceptance (execution pending)

- For each unavailable state above, confirm Settings shows the observed cause and
  a suitable recovery action. Confirm Refresh status reads the current state and
  never starts a recording or removes Notes. With no reported cause, expect the
  explicit unknown explanation rather than a guessed pairing or installation error.
- Expand Technical details and compare support, activation, pairing, installation,
  reachability and queued state/audio counts with the test devices. Reproduce an
  activation or background transfer error when possible; verify its safe domain,
  code and observed time. Successful activation clears the activation error;
  a historical transfer error remains labelled separately and cannot change current
  availability. Unreported facts say Not reported. Do not provoke an error by
  deleting a user's only audio copy.
- For unreadable received audio, missing/expired Watch source audio, and an observed
  local save failure, confirm Note details separates the cause, recovery guidance,
  transfer cycle and retry history from webhook Delivery attempts. Retry sync
  clears the active cause for its new cycle. A valid repair keeps historical retry
  causes and a Sent Receipt. Missing source audio must not be promised recoverable.
- Check both collapsed and expanded sections with VoiceOver and the largest
  accessibility text sizes. Actions and disclosure controls must remain reachable,
  labels/values must be read in order, and identifiers/codes must wrap without
  clipping. Verify these on physical iPhone and paired Watch; simulator XCTest and
  Maestro evidence does not sign off OS pairing reports, radio transfers or spoken
  VoiceOver/Dynamic Type acceptance.
