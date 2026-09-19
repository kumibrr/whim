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
