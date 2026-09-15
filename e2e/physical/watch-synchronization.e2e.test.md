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

All six cases block release until evidence is recorded. Simulator passes do not
satisfy real transferFile, locked-device background execution, or paired race acceptance.
