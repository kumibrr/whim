# iPhone presentation acceptance

Status: pending physical-device execution. These cases supplement the automated
Task 7 tests; they are not evidence of a release pass.

Record the build SHA, iPhone model/iOS version, tester, date, result, and a
non-sensitive evidence path for each execution.

## Recording session configuration on iOS 27

Preconditions: a physical iPhone with microphone permission granted. Skip webhook
setup or use a controlled test destination and non-sensitive spoken fixture audio.

1. Cold-launch Whim and tap Record. Verify capture starts without a generic error
   or `SessionCore` invalid-parameter (`4294967246` / `-50`) error.
2. Speak for at least two seconds, tap Stop, and play the resulting Note. Verify
   the audio is audible and the duration is correct.
3. Start another Recording Session after playback and repeat Stop and playback.

Regression: `.record` with `.spokenAudio` failed during category configuration on
a physical iPhone 15 running iOS 27, while the simulator accepted the combination.
The 64 kbps AAC setting also failed encoder preparation at 16 kHz mono. Recording
now uses 32 kbps. The automated audio-adapter tests check the actual iOS session's
recording mode and encode/decode fixture audio using the production settings;
microphone capture and playable audio still require this physical acceptance case.

Targeted verification, 2026-09-19: the user confirmed Record, Stop, and audible
playback on an iPhone 15 running iOS 27, using the working-tree build based on
`eeed662` with both
the default session mode and 32 kbps AAC fixes. Evidence: this debugging session's
device installation and the user's "It works" response. The separate
repeat-after-playback step and the rest of this document remain pending.

## Playback releases the audio session

Preconditions: a playable local Note and another audio app that supports resuming
after an interruption. Use non-sensitive fixture audio.

1. Start audio in the other app, then play the Note in Whim.
2. Press Stop playback. Verify Whim stops and the other app receives the end of
   the interruption and can resume according to its own playback policy.
3. Repeat, allowing the Note to finish naturally.
4. Start playback again, then start a Recording Session. Verify playback stops,
   capture works, and a late playback completion does not interrupt capture.

Expected: playback holds the audio session only while needed; stopping or
   finishing releases it with notification to other audio apps.

Closest deterministic coverage:
`packages/WhimCore/Sources/WhimCore/Playback/PlaybackAdapter.test.swift` exercises
Stop, completion, preparation/construction failures, and stale callbacks through
the platform-adapter seam. The installed record-and-review journey verifies
playback controls through the real app.

## Capture feedback and accessible Note summaries

1. With VoiceOver enabled, focus a Note row. Verify its title, date/time, source,
   duration, delivery/review status, and any local-audio error are announced.
2. Start and stop capture. Verify visible and haptic feedback agree with capture.
3. Interrupt capture and separately allow it to reach the five-minute limit.
   Verify the saved-Note feedback and contextual permission offers still appear
   when appropriate; denied permissions are not requested again.
4. Repeat navigation with large Dynamic Type, Dark Mode, and Reduce Motion.
   Verify controls remain reachable and statuses remain understandable.

Closest deterministic coverage: native IPhoneModel integration tests for capture,
reset, permission deferral, suspended snapshots and restarted observation;
RecordingService limit tests; and the installed iPhone Maestro journeys.
The record-and-review journey also verifies modal confirmation isolation.
VoiceOver announcements and haptic perception require physical acceptance.

## Recording-first monochrome interface

Status: pending physical-device execution. Simulator checks do not prove haptics or live microphone responsiveness.

1. Launch after onboarding. Expect a black screen, a still white horizontal line, glass Record at bottom center, icon-only Settings at top right, and the exact hint "scroll to see previous notes.".
2. Start capture. Sustain a steady vowel: after settling, the curve should hold its shape. Change only loudness: its height should change. Change pitch or vowel at similar loudness: its middle should reshape. Remain silent: it should settle flat. Both edges taper almost to zero. No motion should occur merely because time passes. Expect the full-width line to react to input and settle toward a line during silence, without growing from left to right. Only Stop and Discard are reachable, including with VoiceOver and an attempted history swipe.
3. Open Discard, choose Keep recording, then Stop. Expect uninterrupted capture after canceling Discard and a saved Note after Stop. History must remain closed. Repeat with interruption and the five-minute limit; playable audio remains recoverable and the home returns to idle.
4. Slowly drag upward from the hint. Expect the sheet to track the finger. Cancel a short drag: no opening haptic. Complete a drag: one soft opening haptic. Scroll the open list: no dismissal or repeated opening haptic. Drag the handle downward or use Close history to dismiss.
5. Open history by tapping the hint and with VoiceOver. Play a Note, then another: only the second plays. Close history: audio stops. Open a Note's details: the inline player stops. Start capture after playback: capture takes audio-session ownership.
6. Inspect long titles, failed and recovered Notes, and expired local audio. Expect readable title/date/time, duration/source/status, reachable Retry/review/detail actions, and disabled playback when audio is unavailable. Playback or review alone must never send a recovered Note.
7. Enable the largest accessibility text size. Expect stacked card metadata and player, full spoken titles, readable status, and usable controls. Enable Reduce Motion: no decorative continuous motion. Enable Reduce Transparency: opaque dark surfaces with readable boundaries and text.
8. On iOS 18 inspect the material fallback; on a system with native Liquid Glass inspect the native controls and cards. Both retain the same actions and monochrome appearance, except for the red Delete icon in Note detail. Record OS/device versions and visual evidence with acceptance results.

## Input-driven waveform capture regression

Status: pending physical iPhone execution. Tone means measured tonal brightness,
not an exact musical pitch tracker.

1. On a physical iPhone, record steady, low and high vowels at similar volume,
   then vary loudness at steady pitch. Verify stable, input-driven shapes and soft
   transitions. Let elapsed time advance without changing input: no phase drift.
2. Stop and play the Note, including after a short sound followed by silence.
   Verify audible audio, correct duration, and retention of meaningful short Notes.
3. Repeat after playback, after an interruption, and after a microphone route
   change (wired/Bluetooth input when available). Captured audio must be finalized
   through the existing interruption flow; another Recording Session must start.
4. Discard during capture, then start again. Verify no old audio or tone leaks
   into the next Recording Session. Repeat with Reduce Motion.

Closest deterministic coverage: RecordingSignal tests use known frequencies,
gains and buffer phases; PCMRecorderHardware integration tests feed raw PCM through
production analysis/conversion/AAC writing and test cleanup/interruption; native
IPhoneModel integration tests verify progress propagation and session reset.

## Note detail card and toolbar

Status: pending physical iPhone execution.

1. Open a Note from history. Compare its card with history: the glass surface,
   title, date, source, duration, status and waveform player match. Detail metadata
   does not act as an Open button. Delivery information and recovery instructions
   appear below the card.
2. Verify the toolbar has Back on the left, no Whim heading in the center, and a
   red trash icon on the right with the same native glass treatment as Back.
   VoiceOver announces “Delete Note”. Check both native Liquid Glass and an
   iOS 18 device, and repeat with Reduce Transparency and accessibility text sizes.
3. Play and stop audio from the detail card, then leave while playing. Playback
   stops. Expired or unavailable audio cannot play; the card explains why.
4. Cancel deletion of an unsent Note and verify it remains playable. Confirm
   deletion and verify return to history. Delete a sent Note and verify immediate
   removal. Review a recovered Note and verify Send remains an explicit action.

Closest deterministic coverage: NoteDetailModel integration tests cover waveform
loading, playback and audio disappearance; record-and-review, recovered-review and
Watch synchronization iPhone journeys cover the shared player and deletion paths.
