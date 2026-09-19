# iPhone presentation acceptance

Status: pending physical-device execution. These cases supplement the automated
Task 7 tests; they are not evidence of a release pass.

Record the build SHA, iPhone model/iOS version, tester, date, result, and a
non-sensitive evidence path for each execution.

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
