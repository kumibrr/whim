# Visible Watch audio synchronization

The iPhone must show a Note as soon as its Watch metadata arrives, even while its audio is missing. Audio Synchronization is independent of webhook Delivery: a Watch Receipt stays Sent even when iPhone audio synchronization fails.

## Behavior

- Persist a metadata-only Note with an explicit local Audio Synchronization state. This state never claims that playable local audio exists. Show “Waiting for Watch audio”; disable playback, title enrichment and local webhook Delivery until durable, validated audio arrives.
- A cycle contains at most three total transfers, including the initial corrupt transfer: at most two automatic resends. A queued request waits for Watch without consuming further transfers. Only a distinct corrupt or unavailable response to the current request advances the cycle. Duplicate events, stale responses, recovery and reconnection do not exhaust the budget.
- After the third unsuccessful transfer, show “Sync failed”. Keep the Note visible, including in the Failed filter. “Retry sync” starts a fresh cycle of up to three transfers; it is also available while waiting. Delete requires confirmation and propagates the existing Note-ID tombstone to Watch. Late metadata/files cannot resurrect it.
- A synchronization failure occupies the card's status position, replacing the Delivery label. Synchronization retry appears only in Note details as a compact Liquid Glass icon beside “Retry sync”. Confirm Note deletion with a native alert offering Cancel and Confirm delete.
- Valid audio repairs the same Note, enables playback and normal processing, and preserves any existing Receipt. Other Notes continue synchronizing and delivering throughout.
- Persist request identity and retry progress across process restarts. Hold Watch audio until a valid copy is durably accepted; never acknowledge corrupt audio as durable. If the Watch has no readable source, return an explicit unavailable response rather than silently waiting forever.
- Persist the Watch handoff hold independently of file readability. A metadata acknowledgement never releases it; valid audio acceptance, deletion or reset does. An already accepted handoff remains accepted across repeated metadata synchronization.

## Approach

Use the existing Note store with an explicit optional synchronization state and additive SQLite migration. This lets queries, details, events, filters and deletion use the existing Note interface while distinguishing metadata-only Notes from Notes with finalized local audio. A separate UI-only placeholder would lose recovery state and duplicate Note queries; a generic local-audio error would conflate pending transfer, corruption and expiration.

Add versioned peer audio-request/unavailable messages and an optional request identity on file metadata. Keep retry accounting separate from webhook Attempts. Reconstruct outstanding requests from persisted Note state if process termination interrupts outbox creation. Existing unknown-message handling safely ignores the new messages on older builds; both updated endpoints are required for explicit resend support.

## Verification

Use the approved WhimCore, cross-device protocol, presentation and installed-app seams. Integration tests compose SQLite, real files and peer merge services; only the system transport is replaced. Cover metadata visibility, receipt independence, three unsuccessful transfers, duplicate/stale responses, restart recovery, offline waiting, successful repair, manual restart, deletion/reset and unaffected Notes. Maestro covers waiting, exhausted synchronization, manual repair and deletion through the compiled iPhone app. Physical paired-device cases cover actual Watch Connectivity and background suspension.

## Note detail retry history

Show one row under Delivery details for each requested audio resend, with its outcome and request time. The original transfer is not a retry. Retain rows across manual cycles, successful repair and process restarts; repeated callbacks never duplicate them. A request waiting for Watch has a waiting outcome, and a manual replacement supersedes that request without treating disconnection as a failure. These rows remain distinct from webhook Attempts. The detail screen omits the redundant transfer-count error sentence; its smaller retry control retains a 48-point minimum touch target.
