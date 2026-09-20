# Independent Apple Watch capture acceptance

Run on a signed watchOS 11+ physical Watch with the companion iPhone disconnected.
Record device/watchOS version, build, elapsed times, and observed results. These cases
block release even when the deterministic Watch model and installed-app suites pass.

1. Grant microphone permission, quit, then deliberately launch Whim. Expect one
   Recording Session, immediate elapsed progress, and a distinct start haptic.
2. Lower the wrist for at least 60 seconds while speaking. Raise it and reopen Whim.
   Expect the same active recorder and continuous audible content. Stop, play the
   local Note, and verify both pre/post wrist-down speech. Confirm Setup required
   without configuration and Queued with configuration while offline.
3. Start again and remain wrist-down through five minutes. Expect the warning haptic
   near the limit and one safely finalized, playable Note at the limit. Reopening
   must not start another capture; use Record deliberately to start again.
4. Interrupt capture with Siri, a call, and an audio-route change. For interruptions,
   expect playable audio preserved and no automatic microphone resume. Verify a new
   deliberate Record command works afterward.
5. Play a recent Note on supported Watch speaker/headphone routes. Verify audio,
   Stop Playback, completion, and recording after playback; Whim releases the audio
   session when playback ends. Simulator fixtures prove the UI/state only.
6. Verify VoiceOver focus/labels, large text, sufficient contrast in light/dark mode,
   Reduce Motion, haptic plus visible start/stop feedback, and destructive confirmation.
7. With a real configured webhook, capture and observe direct Sent while iPhone is
   disconnected. Remove/revoke configuration and confirm failures stay recoverable.

Configuration transfer and Last synchronized acceptance belong to Task 9. Until
synchronization exists, the Watch explicitly shows Last synchronized: unavailable.

## Launch distinction

Cold process/window launch starts capture after permission. A warm app-icon re-entry
uses the same scene activation signal as wrist-down and therefore restores existing
capture or leaves the app idle after Stop, Discard, or interruption. Use the visible
Record action to start another Recording Session. Explicit complication/intent/URL
capture entry points belong to Task 10; do not count warm icon re-entry as automatic
capture in this acceptance run.

## Immediate discard

During capture, verify Discard is red with a minimum 100 × 44 point target. Tap beside the text within the button: capture ends immediately without confirmation, and recent Notes contains no new Note. Repeat with VoiceOver.

## Double-tap recording control

On a Watch that supports the system Double Tap gesture, enable Double Tap in Settings
and grant Whim microphone access. With the capture screen visible and wrist raised:

1. Launch Whim and double-tap thumb and index finger while recording. Expect Stop
   to finalize one Note and show Record without scrolling to Previous Notes.
2. Double-tap again while idle. Expect a new Recording Session, elapsed time, and
   Stop without scrolling. Double-tap once more to save the second Note.
3. Scroll manually to Previous Notes and verify both Notes are present and playable.
4. Return to capture and repeat after wrist-down/wake. Verify the gesture stops the
   existing Recording Session and never triggers Discard.

Record device/watchOS version and a video showing the gesture and resulting state.
The installed-app companion test exercises repeated start/stop through the targeted
buttons and checks that two Notes are saved without leaving capture. Physical
acceptance verifies the gesture binding and recognition: watchOS 27 simulator
`XCUIDevice.perform(handGesture: .doubleTap)` did not activate even a minimal
primary-action Button during verification.

## Liquid Glass capture transition (OS 26 and later)

1. From idle, tap Record. Expect the capture glass to remain visually continuous as its symbol becomes Stop, while a red Discard glass pill emerges directly below it. It must not fade in as an unrelated control or merge with Settings.
2. Tap Discard once. Expect capture to end immediately and the pill to merge back into the capture control. Repeat rapidly, then Stop; no leftover or duplicate controls may intercept taps.
3. Enable Reduce Motion. Repeat: controls change without the morph animation. Enable Reduce Transparency: controls remain legible with opaque surfaces.
4. Verify the existing large hit targets and VoiceOver labels. On pre-26 systems, retain the existing material capture button and plain red Discard without morphing.
5. Record a slow-motion screen capture on physical OS 26 hardware for the visual transition; automated journeys cover the resulting state and operable controls.

## Capture-first launch and error presentation

Measure first capture-frame appearance and actual microphone onset separately on cold and warm launches, with empty and populated stores. First activation with granted permission must capture while old audio recovery/synchronization continues. Stop must respond before that work finishes. Returning after wrist-down or Stop must not start a second session.

Deny microphone permission and launch: verify the error container/action sits in the upper half and tapping the whole glass card opens device-specific guidance. Grant access in Watch Settings and return: the error clears, and Record starts explicitly after the initial activation. Verify glass, older-OS material fallback, Reduce Transparency, VoiceOver, and large text. The compact message must wrap at large text sizes. Tap near the card edge as well as its text: both trigger recovery. Verify VoiceOver announces the action and offers Dismiss error for auxiliary failures; a horizontal swipe dismisses those failures without triggering retry. Stop/Discard must remain accessible. Include storage-full guidance followed by Check again after freeing space. Check initial speech preservation and wrist-down continuity on hardware.

Compact errors: verify the glass card fits its message without an empty scrolling area or a separate action row. Tapping anywhere on the card runs its recovery action; repeated taps during work are disabled.
