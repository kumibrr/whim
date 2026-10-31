# iPhone recording system entry points

Status: **Pending physical acceptance.** Automated tests do not establish locked-device microphone operation or a physical Action-button press.

Record the build commit, signing identity, iPhone model, iOS version, paired Watch model/watchOS, and pass/fail evidence for every case. Use non-sensitive speech. Never include webhook credentials in evidence.

## Setup

1. Install the signed build on an iPhone running iOS 18 or later; use an Action-button-capable iPhone for the button cases.
2. Open Whim, finish onboarding, and grant microphone permission. Enable Live Activities for Whim in Settings. A webhook is optional: Notes should remain recoverable without one.
3. Customize the Lock Screen, replace one bottom control with Whim's **Record a Whim**, and save.
4. In Settings → Action Button → Shortcut, select **Record a Whim** for Whim. Verify **Stop Whim Recording** is separately discoverable in Shortcuts.
5. For the paired Watch, allow Live Activities/Smart Stack presentation and install Whim's complication on a supported face.

## LS-1 — Start from the locked iPhone

Lock the iPhone after its first unlock since restart. Cover Face ID to avoid accidental authentication. Activate the Whim Lock Screen control, speak a short phrase, wait ten seconds, and press **Stop** in the Live Activity. Unlock and play the resulting Note.

Expected: capture begins while still locked; a Live Activity shows advancing elapsed time and Stop; no navigation into Whim is needed. One playable Note contains the phrase, and the activity disappears after Stop. Record any system authentication requirement as a limitation/failure, not as successful locked capture.

Evidence: external video showing lock state, activation, elapsed time, Stop, and playback; note the device/OS. Repeat with Whim already running, after ordinary process termination, and offline.

## AB-1 — Start with the Action button

With the assigned shortcut, press and hold the physical Action button as required by iOS. Repeat while unlocked and while locked with Face ID covered. Speak, then press and hold the Action button again and play the resulting Note.

Expected: the first invocation starts capture and its Live Activity. The second invocation stops capture, ends the activity, saves exactly one playable Note, and starts Delivery without opening Whim. A configured, reachable webhook receives the Note and Whim shows Sent. Repeat after ordinary process termination, offline (Queued), and without configuration (Setup required). Capture external video that includes both hardware presses; simulator intent execution is insufficient evidence.

## RP-1 — Repeated and alternating entry points

Start using the Lock Screen control, then invoke the Action button to stop and send. Invoke the Action button again to start a new session, then use the Lock Screen control to stop it. Repeat using Siri's Record shortcut as the second invocation. Start in Whim and stop using the Action button on another run. Open Whim during recording and return to the Lock Screen.

Expected: each active-session invocation stops and finalizes exactly one Note; each idle invocation starts a fresh session with a new elapsed timer. Saved audio is preserved and Delivery begins through the normal workflow. On a separate run, stop through the Live Activity; repeat Stop through its App Shortcut and verify it does not create a Note or begin another capture. Watch repeated Record continues to focus its existing local session.

## PM-1 — Permission recovery

Deny microphone permission and invoke each entry point. Follow the foreground guidance, grant permission in system Settings, and retry. Repeat from an installation where permission has never been requested.

Expected: no capture starts before permission; the system presents an explanation and route into Whim, respecting authentication. Retrying with permission starts capture. Evidence includes the explanation and resulting Note, not merely a successful app launch.

## LA-1 — Live Activities unavailable

Disable Live Activities for Whim. Invoke the Lock Screen control and the Action-button shortcut independently. Restore Live Activities and retry.

Expected: failed activity creation leaves no running microphone capture and no empty Note. A recoverable explanation directs the user to Whim/settings. After restoration, capture succeeds. Under the current v1 specification, in-app capture also requires its Live Activity.

## LC-1 — Lifecycle and recovery

Start capture and verify Lock Screen elapsed time and expanded Dynamic Island Stop. Discard in Whim on a second run. On separate runs trigger an audio interruption and reach the five-minute limit. Terminate the process during capture, then reopen Whim.

Expected: Stop, Discard, interruption, and maximum duration end the activity and preserve/discard audio according to the v1 recording rules. Reopening removes orphan activities and exposes recoverable audio through normal recovery. The first-launch permissions/authentication required immediately after reboot are recorded separately from ordinary locked operation.

## DI-1 — Voice waveform in every Dynamic Island presentation

On a Dynamic Island iPhone, start a Recording Session and return to the Home Screen. Alternate silence, soft speech, loud speech, and different vowel sounds. Inspect compact presentation, then touch and hold to expand. Start another app's Live Activity to expose Whim's minimal circle.

Expected: compact presentation has advancing red elapsed duration on the left and the voice waveform on the right. Expanded presentation shows the larger semibold red elapsed duration inset from the upper-left corner beside the camera cutout, and the app's rounded red square Stop control within a translucent 56-point circular surround centered over the full-width waveform using the same voice contour as Whim. The complete circle fits below the timer with visible space above and below it, including on the smallest supported Island. The minimal circle shows the small waveform. Silence flattens the trace to a thin line; voice changes its amplitude and contour. The original elapsed timer continues across presentations. ActivityKit controls refresh timing; record actual responsiveness on the device rather than claiming app-frame-rate animation from simulator tests.

On separate Recording Sessions, tap the elapsed duration, centered Stop square, left, right, and padded edges of the expanded waveform. Each tap stops microphone capture, saves exactly one playable Note, and dismisses the activity without opening Whim. The system-owned camera/cutout is outside the content hit region. Compact/minimal taps keep the normal iOS app-opening interaction.

Lock the iPhone while recording. The Lock Screen uses the same full-width voice waveform, centered translucent Stop circle and red elapsed time. Repeat the silence/speech checks and tap the timer, waveform edges and Stop square on separate sessions; each stops and saves once. Confirm this also works at accessibility text sizes and in the paired Watch Smart Stack's smaller presentation.

Repeat with VoiceOver and Reduce Motion. The expanded waveform and Lock Screen are each one action named **Stop Whim Recording**, with a hint that it saves the Note. VoiceOver also announces the Lock Screen action's current elapsed duration. The compact duration remains legible through the five-minute limit. Verify that paired Watch Stop still works.

Evidence: external video of speech/silence, all three presentations, and each tap position followed by the resulting playable Note. Mark this case pending until checked on hardware; automated content, rendering, and Stop-intent tests do not establish system refresh timing or physical hit coverage.

## WS-1 — Watch Smart Stack and complication

During an iPhone recording, inspect the paired Watch Smart Stack and invoke Stop there where supported. Independently inspect idle, recording, and failed-Note states of the Watch complication, then tap it while the Watch app is idle and while already recording.

Expected: Smart Stack Stop addresses the iPhone Recording Session. The complication starts/preserves a local Watch session; idle has a Whim mark, active has elapsed time, and failed Notes have a non-color-only attention indicator. No per-second widget reload is required. Verify VoiceOver, large text, and Reduce Motion.

## Automated evidence and remaining limits

- `WhimSystemSurfaceTests` executes the production Record/Stop intents and control action with real WhimService, SQLite, and audio files; only platform boundaries are fixtures.
- `scripts/verify-system-surfaces.py` checks built extension embedding, App Groups, Live Activity support, and extracted shortcut metadata.
- `ComplicationLaunchUITests` supplies a DEBUG-only launch context to the installed Watch app and verifies capture and invalid-route behavior. watchOS 27 Simulator rejected both XCTest URL opening (no process ID) and `simctl openurl` (LSApplicationWorkspace error 115), even with the registered scheme. Warm URL reentry is covered through WatchModel; actual face taps require WS-1.
- `shortcuts-and-live-activity.e2e.test.yaml` exercises installed Live Activity Stop where the simulator exposes the surface. `action-button-stop-and-send.e2e.test.yaml` invokes the production Record intent through a DEBUG fixture-only link and verifies capture, repeat-to-send, playback, and a fresh session. This link does not prove OS shortcut dispatch or locked execution. Lock Screen customization and a physical Action button remain cases LS-1/AB-1.
- Activity lifecycle and reconciliation, permission/activity failure, attention projection, and DEBUG-only latency have deterministic companion tests. Hardware latency figures must be captured on the physical devices; fixture timings are not product performance claims.
