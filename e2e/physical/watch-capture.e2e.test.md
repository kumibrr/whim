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

## Corner complication

Status: pending physical-device execution. The previous shared-canvas previews
used custom-drawn lettering and were rejected. The current implementation restores
plain Text through WidgetKit's native label and keeps the compact logo straight.
watchOS controls the font, size, curve and placement, including any native radial
offset between the logo and label. The four published widget kinds remain registered
so existing face selections survive upgrades.

Simulator acceptance: on 2026-11-15, the local build was installed on the paired
Apple Watch Series 9 (41 mm), watchOS 27.0. Infograph displayed the straight
compact logo and native curved Record label. The native label remains offset
from the logo; this is not a claim that radial centering is fixed.
Evidence: [native Record label](../../artifacts/complication-previews/watch-series9-41mm-native-record.png).

Size follow-up: increased the straight idle mark from 18 to 21 points wide,
about 17%, while preserving the native Record label. Verified the larger mark
on the same 41 mm Infograph face without visible clipping.
Evidence: [larger straight logo](../../artifacts/complication-previews/watch-series9-41mm-larger-logo.png).
The updated size regression failed at 18 points before the change, then all 27
Watch tests passed at 21 points. `npm run test:all` also passed with the focused
app-update iPhone flow and both complication-launch Watch UI cases selected;
optional simulator diagnostic collection was disabled for this local run.

Automated validation: both new regressions failed against the custom lettering,
then all 27 Watch tests passed after restoration. `npm run test:all` passed with
the app-update iPhone flow and both complication-launch Watch UI cases selected.
The rerun disabled optional simulator diagnostic collection after Xcode crashed
while collecting diagnostics on the first attempt. All 22 system-surface tests,
nine hardware-boundary tests and the selected UI cases passed without failures
or skipped tests. Physical-device execution remains pending.

1. Run on a 41 mm Watch and a larger Watch, recording model and watchOS version.
   Verify existing Corner selections survive upgrading, all four published entries
   remain available, and Circular support remains unchanged.
2. While idle, verify the small logo stays straight and visible, with the native
   Record label following the face's bezel. Compare its typography with adjacent
   system complications. Check cropping and overlap in every corner, after
   wrist-down and returning from the app. Record any placement offset controlled
   by watchOS; custom-drawn lettering is not an acceptable workaround.
3. Tap with microphone access granted: expect immediate capture. Return to the
   face and verify the red glyph sits close to the curved elapsed-time label,
   without overlap. Tap again during capture: expect the existing Recording
   Session. Stop in Whim and verify one playable Note and the idle layout.
   Confirm all four entries refresh together; none may keep a stale timer.
4. Produce a failed Note. While idle, verify a monochrome white warning symbol
   with Check Notes. While recording, verify the warning is beside the timer.
   Check tinting, Always On dimming and VoiceOver in every corner. VoiceOver must
   announce the actual elapsed duration; refocus after several seconds and verify
   it advances. Stop and warning retain their tight bezel gap and orientation.

Deterministic regression coverage compares the idle label with unmodified Text,
checks that the main image canvas contains only the straight compact logo, and
retains circular-mask, family/kind registration, position retention, all-kind
reload and Stop/warning-gap coverage. Installed-app UI coverage verifies launch,
capture and saving. ImageRenderer cannot prove WidgetKit's native label rendering
on a face; simulator and physical acceptance remain required.

## Capture control bounds and history toolbar

On the normal capture screen, verify the touch target and VoiceOver focus cover
the full 72 point glass circle rather than only its center symbol. Tap between
the symbol and the circle's edge to Stop, then repeat to Record. Scroll to
Previous Notes and verify the first Note clears the native toolbar by at least
44 points, including with large text. The installed Watch UI cases cover the
control bounds, off-center taps, and toolbar clearance; physical VoiceOver
acceptance remains required.

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

## Logo waveform

On a physical Watch with microphone access granted:

1. Stop any Recording Session. Expect the idle capture screen to show the Whim
   logo waveform — flat lead-in and lead-out, the logo curve and its floating
   dot — as a stroke heavy enough to read as the app mark, with no "whim"
   wordmark. It sits above the Record button with space on both sides, clear of
   the clock and the control. It must not animate.
2. Tap Record in a quiet room. Expect the mark to travel into a flat line rather
   than being swapped out, and to stay flat until somebody speaks nearby.
3. Speak at varying loudness. Expect a voice trace that rises and falls with
   volume, moves only vertically and holds still for steady input.
4. Stop and Discard. Each time, expect the line to travel back into the logo.
   Repeat with Reduce Motion: the states change without animation.

Closest deterministic coverage: WhimCore LiveWaveform tests cover the resting
logo, the silent flat line, the voice trace and the travel between them;
WatchModel integration tests cover loudness and tone propagation and their
reset between Recording Sessions.

## Microphone permission explanation

Status: pending physical-device execution.

With microphone permission undecided, launch Whim. Verify the capture screen
explains why access is required and presents a neutral Continue action. Tap
Continue and verify the watchOS system permission prompt appears. Repeat from
undecided permission with both grant and denial. Denial must leave recording
blocked with the existing Settings guidance; granting access must allow capture.
The installed Watch UI regression resets system microphone authorization and
checks the neutral action without the debug permission adapter.

## Silence auto-stop (issue #50)

Status: pending physical paired-device acceptance.

1. On iPhone, open Settings → Apple Watch. Verify Auto-stop after silence is on,
   the default duration is 3 seconds, the slider reaches 2 and 10 seconds in
   one-second steps, and VoiceOver announces the label and duration with units.
   Check large Dynamic Type and disabled-slider presentation. Save each change.
2. Start Watch capture from the app, complication, and App Shortcut. Wait silently
   before speaking: capture must remain active. Speak normally, pause less than the
   selected interval, resume, then remain quiet for the full interval. Verify one
   completed Note, normal stop feedback, and normal Delivery without tapping Stop.
3. Repeat at 2 and 10 seconds. Confirm settings received during capture apply only
   to the next Recording Session. Disable auto-stop and confirm silence requires
   manual Stop. Re-enable and verify the previous duration is preserved.
4. Repeat with quiet speech, in a quiet room, with road noise, and with wind. Verify
   no premature cutoff. Record the environment and observed delay; sustained noise
   may prevent the level meter from identifying silence. Tune the internal levels
   only with deterministic regression coverage for the changed policy.
5. Lower the wrist and let the screen sleep during speech and silence. Verify the
   service still finalizes safely and returns to idle. No Speech permission is needed.
6. Disconnect the phone after settings synchronize, restart Whim on Watch, and repeat.
   Verify the cached settings still apply. Change settings while disconnected, reconnect,
   and verify pending changes apply and acknowledgement updates the phone's status.
7. Exercise manual Stop, immediate Discard, an audio interruption, and route changes
   near the silence boundary. Expect at most one local Note and one logical Delivery;
   Discard winning before finalization must leave no Note. Partial audio remains
   recoverable on failure. Simultaneous cross-device Attempts retain the same Note ID.
8. With continuous audio and with no meaningful audio after launch, verify the
   existing five-minute warning and safe stop still work. Confirm iPhone capture is
   unaffected by Watch auto-stop settings.

Evidence: paired models/OS versions, selected duration, environment, observed stop
latency, resulting Note/Delivery state, accessibility result, and wrist-down result.
