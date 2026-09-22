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

With the assigned shortcut, press and hold the physical Action button as required by iOS. Repeat while unlocked and while locked with Face ID covered. Speak, then use the Live Activity's Stop control and play the Note.

Expected: same recording and activity behavior as LS-1. Repeat after ordinary process termination and offline. Capture external video that includes the hardware press; simulator intent execution is insufficient evidence.

## RP-1 — Repeated and alternating entry points

Start using the Lock Screen control, then invoke the Action button twice. Reverse the order on another run. Open Whim during recording and return to the Lock Screen.

Expected: the original elapsed timer continues; no second session, unexpected Stop, or Discard occurs. Stop once; exactly one Note is finalized. Repeat Stop through its App Shortcut and verify it does not create a Note or begin another capture.

## PM-1 — Permission recovery

Deny microphone permission and invoke each entry point. Follow the foreground guidance, grant permission in system Settings, and retry. Repeat from an installation where permission has never been requested.

Expected: no capture starts before permission; the system presents an explanation and route into Whim, respecting authentication. Retrying with permission starts capture. Evidence includes the explanation and resulting Note, not merely a successful app launch.

## LA-1 — Live Activities unavailable

Disable Live Activities for Whim. Invoke the Lock Screen control and the Action-button shortcut independently. Restore Live Activities and retry.

Expected: failed activity creation leaves no running microphone capture and no empty Note. A recoverable explanation directs the user to Whim/settings. After restoration, capture succeeds. Under the current v1 specification, in-app capture also requires its Live Activity.

## LC-1 — Lifecycle and recovery

Start capture and verify Lock Screen elapsed time and expanded Dynamic Island Stop. Discard in Whim on a second run. On separate runs trigger an audio interruption and reach the five-minute limit. Terminate the process during capture, then reopen Whim.

Expected: Stop, Discard, interruption, and maximum duration end the activity and preserve/discard audio according to the v1 recording rules. Reopening removes orphan activities and exposes recoverable audio through normal recovery. The first-launch permissions/authentication required immediately after reboot are recorded separately from ordinary locked operation.

## WS-1 — Watch Smart Stack and complication

During an iPhone recording, inspect the paired Watch Smart Stack and invoke Stop there where supported. Independently inspect idle, recording, and failed-Note states of the Watch complication, then tap it while the Watch app is idle and while already recording.

Expected: Smart Stack Stop addresses the iPhone Recording Session. The complication starts/preserves a local Watch session; idle has a Whim mark, active has elapsed time, and failed Notes have a non-color-only attention indicator. No per-second widget reload is required. Verify VoiceOver, large text, and Reduce Motion.

## Automated evidence and remaining limits

- `WhimSystemSurfaceTests` executes the production Record/Stop intents and control action with real WhimService, SQLite, and audio files; only platform boundaries are fixtures.
- `scripts/verify-system-surfaces.py` checks built extension embedding, App Groups, Live Activity support, and extracted shortcut metadata.
- `ComplicationLaunchUITests` supplies a DEBUG-only launch context to the installed Watch app and verifies capture and invalid-route behavior. watchOS 27 Simulator rejected both XCTest URL opening (no process ID) and `simctl openurl` (LSApplicationWorkspace error 115), even with the registered scheme. Warm URL reentry is covered through WatchModel; actual face taps require WS-1.
- `shortcuts-and-live-activity.e2e.test.yaml` exercises installed Live Activity Stop where the simulator exposes the surface. Lock Screen customization and a physical Action button remain cases LS-1/AB-1.
- Activity lifecycle and reconciliation, permission/activity failure, attention projection, and DEBUG-only latency have deterministic companion tests. Hardware latency figures must be captured on the physical devices; fixture timings are not product performance claims.
