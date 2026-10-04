# Paired-device test guide

Run these procedures on the candidate build using physical devices. The case numbers follow the rows of the [acceptance matrix](paired-device.e2e.test.md). A procedure describes what to try; it does not establish a pass until you report what happened.

## Before the first case

1. Record the installed build's commit SHA, marketing version, and build number. `git rev-parse HEAD` identifies the checkout, but use it as the installed SHA only if that build was made from that checkout. Record any uncommitted changes used to build it.
2. Record your iPhone model and full iOS version, Watch model and full watchOS version, your tester name, and the test date. Install the same candidate on both devices. Identify hardware you do not have, such as an Action button or Dynamic Island.
3. Use disposable Notes and neutral speech, for example “Case one, iPhone, beginning” and “Case one, ending.” Reset and storage-pressure tests can remove data. Set Audio retention to Never except when testing cleanup, so successful audio remains available for playback checks.
4. Configure a controlled receiver following [Receive Whim audio](../../docs/receive-audio.md). Run Test webhook and verify its acknowledgement. On Watch, check that configuration is available and Last synchronized updates. Configuration-test requests are not user Notes; exclude them from delivery counts.
5. For cases that require microphone access, grant it on each device. Unlock the iPhone once after reboot before testing locked capture. Enable Live Activities except in case 7. Keep devices charged during long runs.
6. Record receiver Note IDs, Attempt IDs, times, status codes, and counts without copying audio, titles, credentials, or URL query values into diagnostic logs. Use an external camera to prove lock state, wrist-down behavior, hardware presses, and haptics; a screen recording alone may not show them.

Between cases, restore networking, microphone permission, Live Activities, notification settings, and successful receiver responses unless the next case needs them disabled. Reconfigure and synchronize the webhook after Reset. Keep each case's Notes distinguishable from earlier runs.

One recorded run can support several rows if it exercises all their required actions on the same candidate. For example, case 9's five-minute run can also establish the near-limit haptic observation in case 26; reference the same evidence rather than repeating it solely for another cell.

### Network controls

For completely offline capture, explicitly disable Wi-Fi, cellular, and Bluetooth as needed on both devices and verify that neither can reach the receiver. Airplane Mode may remember enabled Wi-Fi or Bluetooth, and Control Center alone may only disconnect temporarily.

For a disconnected Watch with independent internet, turn off Bluetooth on iPhone in system Settings, keep Watch on working Wi-Fi or cellular, and verify the paired connection is disconnected. If a Wi-Fi connection restores peer reachability, take the iPhone offline or out of range instead. For a Watch with no networking at all, also turn off Watch Wi-Fi and cellular. Restore each radio afterward and verify synchronization; do not infer disconnection from the Airplane Mode icon alone.

### Controlled failure receiver

Cases 21, 22, and 23 need a receiver that can deliberately fail or delay requests. The repository includes a development inbox for this purpose. On a trusted local network, run:

```sh
WHIM_WEBHOOK_HOST=0.0.0.0 WHIM_WEBHOOK_PORT=8787 WHIM_HMAC_SECRET= npm run test-server
```

Use `http://<computer-private-IPv4>:8787/receive` in Whim; use your computer's actual private address, not `127.0.0.1`. Leave optional credentials unset for this isolated test receiver. Open `http://127.0.0.1:8787/` on the computer to inspect requests. The receiver keeps audio in memory and exposes it on its test page; use only disposable speech and do not expose it publicly.

Set subsequent responses to a retryable failure:

```sh
curl -X POST http://127.0.0.1:8787/response \
  -H 'Content-Type: application/json' \
  -d '{"status":503,"delay_ms":0}'
```

Set successful, delayed responses for an in-flight request:

```sh
curl -X POST http://127.0.0.1:8787/response \
  -H 'Content-Type: application/json' \
  -d '{"status":200,"delay_ms":30000}'
```

Restore normal responses after a case:

```sh
curl -X POST http://127.0.0.1:8787/response \
  -H 'Content-Type: application/json' \
  -d '{"status":200,"delay_ms":0}'
```

These controls are available on the development inbox, not the self-hosted reference receiver. Its duplicate flag is an in-memory observation and is not proof of durable server deduplication. Use the reference receiver for case 14. Cases needing device-specific responses require a controlled proxy with verified per-device request routing or an instrumented sender observer; arrange that setup before running them. Metadata `source` identifies the device that captured the Note, not the device sending an Attempt, so both Attempts for a Watch Note can say `apple_watch`.

## 1. App capture

Open Whim on iPhone, tap Record, speak for 10 seconds, and tap Stop. Open history and play the Note. Repeat on Watch; a cold Watch launch with permission may already start capture, whereas warm re-entry after Stop should leave it idle until you tap Record. On each device, also start another Recording Session and tap Discard.

Expected: one intelligible saved Note per stopped Recording Session, correct source and duration, and no Note for Discard. Record the two Note IDs and playback observations.

## 2. Locked control

Customize the iPhone Lock Screen and replace a bottom control with Whim's Record a Whim. Lock after first unlock, cover Face ID, activate that control, and speak. Invoke Record again while capture is active. After 10 seconds, use the Live Activity's Stop, unlock, and play the Note.

Expected: recording begins while still locked; the repeated invocation preserves the original timer; Stop saves exactly one playable Note and removes the activity. Record any required authentication explicitly. Repeat with Whim warm, terminated, and offline. See [locked entry procedures](iphone-system-entry-points.e2e.test.md).

## 3. Action button

On an iPhone with an Action button, assign Whim's Record a Whim shortcut in Settings → Action Button. Press and hold the physical button while unlocked, speak, repeat the invocation, and stop in the Live Activity. Repeat while locked with Face ID covered, after ordinary app termination, and offline.

Expected: each run has one continuing Recording Session and one playable Note, with no accidental Stop or second session. Capture the hardware press on external video. If you lack the hardware, report that variant as untested.

## 4. Shortcuts and Siri

In Shortcuts, create a shortcut containing Whim's Record a Whim action and another containing Stop Whim Recording. Run Record, speak, run Record again, then run Stop. Run Stop again while idle. Repeat by asking Siri to run the two named shortcuts, using names that Siri can distinguish.

Expected: both routes address the same recorder, repeated Record preserves capture, and repeated Stop neither starts recording nor creates another Note. Verify playback. Record recognition or authentication limitations separately from Whim's response.

## 5. Cold entry

Terminate Whim while idle, then invoke the Lock Screen control. Stop and check the saved audio. Terminate again between separate runs through Action button, Shortcuts, and Siri. On Watch, terminate while idle and tap its complication. Speak immediately after the recording indication to check the beginning is preserved.

Expected: each supported route starts capture or presents actionable permission guidance; opening a screen alone is insufficient. Measure invocation-to-visible-state and invocation-to-microphone-onset separately if possible. Record forced-quit restrictions and permission/authentication state; do not combine this with the active-capture termination test in case 19.

## 6. Missing microphone permission

Disable Whim microphone access in iPhone system Settings. Invoke Lock Screen Record, the Record shortcut, and Action button separately. Follow the guidance, grant access in Settings, return, and retry. Repeat denied permission on Watch. A fresh-install variant should start with permission not yet requested; Reset Whim does not reset system permissions.

Expected: no capture or orphan Recording Session without permission, clear device-appropriate guidance, and successful capture after permission is granted. Record the denied and recovered outcomes separately.

## 7. Live Activities unavailable

Disable Whim Live Activities in iPhone system Settings. Separately invoke Record from the locked control, Action button, and inside Whim. Wait briefly, then inspect the app and history. Re-enable Live Activities and repeat.

Expected: under the v1 specification, missing Live Activity support leaves no invisible microphone capture or empty Note; guidance explains how to recover. After restoration, Record and Stop work normally. Note any unavailable system switch rather than assuming the setting changed.

## 8. Complication

Add Whim to a supported Watch face. With Watch idle, tap it, speak, lower the wrist, raise it, and tap it again while recording. Stop and play the Note. Separately inspect the complication while idle, recording, and with a failed Note.

Expected: the first tap starts Watch capture, re-entry preserves it, and one Note is saved. The supported family shows the Whim mark while idle and the specified active/attention presentation; failed state remains understandable without color. Record the face and complication family, since circular and text-capable families differ.

## 9. Locked and wrist-down duration

On iPhone, start capture, lock the phone, and speak a numbered phrase at the beginning and about once per minute until automatic Stop. On a separate run, disconnect Watch from iPhone, start Watch capture, and keep the wrist lowered through the five-minute limit, again speaking at intervals. Check a separate 60-second wrist-down run by raising your wrist before Stop.

Expected: continuous intelligible audio includes speech before, during, and after wrist-down in the shorter run; the same recorder is restored; warning feedback occurs near the limit; the five-minute Note finalizes safely once. Neither device starts another session automatically afterward. Record elapsed time and where any audio gaps occurred.

## 10. Live Activity and Dynamic Island

Start iPhone capture, lock the phone, and watch the Live Activity timer. Unlock and inspect the Dynamic Island, expanding it on supported hardware. Stop from the expanded Island on one run and from the Lock Screen activity on another. Check history and try Stop again if the surface is still briefly visible.

Expected: truthful active state and elapsed time; each Stop finishes exactly once, produces one playable Note, and removes the recording activity. Report Dynamic Island separately if the iPhone does not support it.

## 11. Smart Stack

Run two distinct variants. First record on iPhone while Watch is connected, lower and raise the wrist, open Smart Stack, and use the mirrored Live Activity's Stop where supported. Then record locally on Watch, lower and raise the wrist, inspect Smart Stack, and return to Whim to Stop, using a stack Stop only if that surface provides one.

Expected: the mirrored iPhone Stop finishes the iPhone Recording Session. Watch re-entry preserves its own recorder until Stop. No surface stops the wrong device or starts a second session. Report which surface was actually present; Watch-local capture and a mirrored iPhone Live Activity are different paths.

## 12. Offline then online

After successful configuration sync, disable networking on both devices. Capture and Stop a Note on each; inspect Queued, relaunch, and check that audio remains playable. Restore networking and allow foreground delivery and synchronization. Repeat with both apps backgrounded after Stop.

Expected: Notes survive offline and relaunch, then become Sent. The deduplicating receiver holds one logical record per Note ID; multiple Attempts can be legitimate. Record foreground and background variants separately, including time to delivery.

## 13. Simultaneous capture

With devices paired, start iPhone capture and Watch capture within a few seconds of each other. Say distinct phrases to each, leave both running for 15 seconds, and stop them separately. Play both Notes and inspect the receiver.

Expected: two distinct Note IDs and source values, neither recorder interrupts the other, and both audio files are intelligible. Peer copies of each Note share its original ID; they do not represent additional captures.

## 14. Duplicate delivery

Use the persistent reference receiver and a controlled proxy or request observer that records Note/Attempt IDs without bodies or secrets. With both devices online, record only on Watch and Stop. Keep the iPhone available to import and attempt delivery of that Note. If the first success arrives before a second Attempt starts, repeat with a deliberate server-response delay.

Expected: evidence shows distinct device Attempts for the same Note ID but only one stored receiver Note. Relaunch both; Sent must persist. For full race acceptance, arrange success for one device and failure/timeout for the other, then reverse their response order on a new Note. Also test two successes. A later title update must not trigger another request.

A run with only one Attempt does not prove the race. Device-specific response control needs prepared proxy rules; a normal successful receiver cannot force it. See [direct race acceptance](watch-synchronization.e2e.test.md).

## 15. Transfer ordering

Record a Watch Note while disconnected; Stop and leave it queued. Reconnect in stages, first with apps backgrounded and then foregrounded, and verify one imported Note, playable audio, and eventual Sent. Repeat for another Note.

Expected: the final Note and Receipt are stable regardless of observed arrival order, and synchronization after Sent causes no new delivery. However, radio toggles do not guarantee file-before-state or state-before-file. To sign off both orders, arrange an instrumented physical run that timestamps and controls the Watch Connectivity boundary; record the observed order and resulting state. Without that evidence, report the reconnect result and leave the ordering variants pending. Deterministic order coverage is in `ConnectivityMergeService.integration.test.swift` and `ReceivedPeerFileStore.integration.test.swift`.

## 16. Offline configuration change

Start with endpoint A synchronized to Watch. Disconnect Watch from iPhone while preserving its independent internet. Change iPhone to endpoint B with different test credentials. Record on Watch using A, then reconnect. Repeat on a new Note with A configured to fail; keep B successful.

Expected: a success at A remains Sent and is not resent to B. A failure at A permits iPhone delivery using B after synchronization. Watch configuration and Last synchronized update; history retains the truthful sanitized destination and exposes no credentials or query values. Inspect both endpoints' counts. If Watch cannot use independent internet, report that variant as untested.

## 17. Calls and Siri interruption

On separate iPhone runs, record 10 seconds of speech, receive and answer a call from another phone, then inspect Whim; repeat by invoking Siri during capture. Repeat supported interruption routes on Watch, noting whether the OS actually interrupted its audio session.

Expected when interrupted: a playable interrupted Note preserves prior speech, state and Live Activity end truthfully, and the microphone never resumes automatically. A new deliberate Record works. If an action did not interrupt the audio session, record that observation rather than counting it as interruption coverage.

## 18. Audio route change

Connect a Bluetooth headset and confirm its microphone is the recording input. Start capture, speak, disconnect or power off the headset, inspect Whim, and Stop if it remains active. Play the result and start a new Recording Session. Repeat on Watch with a supported route and, if available, with wired input on iPhone.

Expected: no corrupt finalized audio, recoverable speech captured before the change, and truthful recorder state or actionable failure. If the OS produces an interruption, it follows case 17; a mere route change need not always interrupt. Record actual routes and observed feedback, not just the headset's connection icon.

## 19. Process termination

Use disposable data. Start capture and speak for at least 15 seconds. Abruptly terminate Whim without Stop or Discard, then relaunch. A developer-controlled process termination can reproduce an abrupt exit; separately try an app-switcher force quit. Record the method, since ordinary lifecycle handling may safely finalize instead of producing a crash remnant.

Expected for a playable unfinished Recording Session: a Recovered recording appears and requires review with explicit Send or Delete. Playback alone must not send it. Check receiver counts before and after choosing Send. Repeat and choose Delete. An unreadable remnant must remain a visible local error until deleted. If force quit yielded an ordinary interrupted Note, record that result and arrange abrupt-termination coverage rather than claiming crash recovery passed.

## 20. Storage pressure

Use a spare device with disposable data. Create and verify a baseline playable Note. Fill storage gradually with removable test files, leaving the baseline installed, then start capture close to capacity. Continue until an actual write failure occurs; record the reported free space and failure. Relaunch, inspect history, free the test files, use the recovery action, and record again. Repeat on Watch if test storage can be controlled.

Expected: actionable storage feedback, no false Sent state for lost/unfinalized audio, recoverability of previously saved Notes, and successful capture after freeing space. Merely having low free space is not proof of write-failure behavior. If filling storage cannot trigger a controlled failure, leave that variant pending and arrange boundary fault injection; deterministic recording/store tests cover failure paths.

## 21. Failure notification

Allow Whim notifications and use the controlled receiver returning 503. Keep the paired peer disconnected during an isolated-device run so its Attempts do not obscure retry counts. Record and Stop; background Whim and lock the device. Leave the endpoint failing through the initial Attempt and two automatic retries.

Expected: retries occur no earlier than one minute after the first failure and fifteen minutes after the second; the OS may run them later. After three actual failures, one terminal failure notification contains the title and concise reason, and the failed Note remains visible and playable. Reopen without tapping Retry; no fourth automatic Attempt occurs in that retry cycle. Record times and counts; do not use manual Retry to simulate automatic exhaustion. Repeat on the other device where notifications are supported.

## 22. Notification denial/previews

Run three iPhone variants with distinct Notes: deny notifications; allow notifications with Show Previews set to Never; allow them with When Unlocked. Cause terminal failure as in case 21. Inspect the locked screen before authenticating, then unlock and open Whim. For When Unlocked, cover Face ID until ready to inspect the authenticated state.

Expected: denied permission produces no notification but keeps the failed timeline row. Allowed notifications follow the system's preview policy and do not reveal Note content while previews are hidden. Title/reason remain available in Whim. Record each permission/preview variant, lock state, and observed content.

## 23. Background expiry and Reset

Run these subcases with disposable data and receiver request counts:

1. With responses delayed, Stop a Note and background both apps before delivery completes. Restore successful responses and inspect eventual delivery and recoverable state after relaunch.
2. Set Immediately retention, deliver successfully, allow peer transfer to finish, then background/reopen. Verify audio is removed while title/history remain. Separately use a timed Retention Policy and observe cleanup after its real deadline and an OS wake; do not change the system clock as proof of normal scheduling.
3. Queue a Note for retry, cause a separate terminal failure notification, and begin a delayed in-flight Attempt. Reset Whim on iPhone and confirm. Inspect local Notes, settings, credentials, and notifications; restore successful responses and observe whether any additional old work starts.
4. Repeat reset with Watch disconnected. Verify pending reset feedback, then reconnect and verify completed reset and removal on Watch. Relaunch both and ensure no old Note returns. A request already accepted by the server cannot be revoked; distinguish that from a new post-reset Attempt.
5. Disable Background App Refresh on iPhone and verify foreground capture, delivery, and retention still work. Re-enable it afterward.
6. With a Whim complication on the active Watch face, leave eligible queued work and observe a real scheduled refresh. Record its timing and completion evidence.

Expected: cleanup and retry resume safely; Reset prevents stale work and notifications from restoring erased state. For actual background-task expiration, arrange an instrumented physical run that records the expiration callback during a stalled request and successful recovery on the next launch. Backgrounding, a 30-second response delay, or force quit does not prove the OS expiration path. Leave that subcase pending without callback evidence. See [background maintenance](background-maintenance.e2e.test.md).

## 24. VoiceOver/focus

Enable VoiceOver on iPhone and Watch. Use it to navigate onboarding where available, Record/Stop/Discard, history, playback, Note details, webhook editing/testing, retention, permissions, Watch status, and Reset cancellation. Include a failed and a recovered Note to exercise Retry and explicit review. Open and dismiss history while playing audio.

Expected: meaningful labels and statuses, logical focus order, reachable actions, and no hidden playback after dismissal. Stop and Discard remain reachable during capture; VoiceOver can complete each journey without requiring visual guessing. Record exact controls that are unlabeled, skipped, or lose focus.

## 25. Dynamic Type/contrast

Enable the largest accessibility text size on iPhone and the largest supported Watch text size. Inspect capture, onboarding, history, long titles, failed/recovered states, Note details, every settings section, and destructive confirmations. Open the keyboard in webhook setup. Repeat with Increase Contrast and Reduce Transparency; inspect older supported OS materials and native Liquid Glass where devices are available.

Expected: essential text and controls remain reachable without clipping or overlap, fields remain usable with the keyboard, and statuses are identified by text/symbols rather than color alone. Record each device/OS/settings combination; one current-OS screenshot does not cover the older-OS fallback.

## 26. Haptics/Reduce Motion

On each device, with haptics enabled, run Record → Stop and Record → Discard. On Watch also check the near-limit warning. Open history by completing an upward drag and by tapping its hint; cancel a short drag and scroll an already-open list. Repeat with Reduce Motion, then with Reduce Transparency. On OS 26+, inspect the capture/Discard glass transition; inspect older-OS fallback separately where available.

Expected: visible recording state agrees with haptic feedback; Watch start and near-limit feedback are distinct. History opens with one opening haptic, not on a canceled drag or ordinary list scrolling. Reduce Motion removes morph/travel animations without removing controls or audio responsiveness. Discard remains immediately operable and saves no Note. Describe felt feedback and capture external video for motion; a screen recording cannot prove haptics.

## Reporting a result here

Send the device/build details once at the start of a testing session. For each case, report observations, including failed or unavailable variants:

```text
Session: build SHA ..., version/build ..., any uncommitted changes ...
iPhone: model ..., iOS ...
Watch: model ..., watchOS ...
Tester: ...; date: ...

Case: 2 — Locked control
Setup/variants: warm app, microphone allowed, Live Activities on, Face ID covered
Actions: ...
Observed: timer continued after second Record; one Note; playback contained ...
Receiver: Note ID ..., Attempt count ..., response status ...
Evidence: path to redacted video/screenshots or a written observation
Not tested: cold and offline variants
Requested result: partial / pass / fail
```

We can fill Build SHA, devices, actual Preconditions, Exact actions, Evidence path, Pass/fail, Tester, and Date from your report. Expected result remains the acceptance criterion. A partial result stays Pending with the completed variants noted; unsupported variants are described explicitly. Missing details are not inferred. Evidence can be an explicitly labeled written observation if you have no media; no file path is invented. Reuse session details only while the installed build and devices remain the same.

Store written observations or redacted media under `evidence/<build-sha>/case-<number>/` when available. Keep credentials and endpoint query values out of chat reports and diagnostic evidence; receiver counts and neutral test speech are sufficient to describe the results.
