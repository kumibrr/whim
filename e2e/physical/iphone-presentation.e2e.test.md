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
3. Verify Discard is red and its full 120 × 56 point area responds, including beside the text. Tap it once: expect immediate return to idle, no confirmation, and no saved Note. Start again and Stop; expect a saved Note. History must remain closed. Repeat with interruption and the five-minute limit; playable audio remains recoverable and the home returns to idle.
4. Slowly drag upward from the hint. Expect the sheet to track the finger. Cancel a short drag: no opening haptic. Complete a drag: one soft opening haptic. Scroll the open list: no dismissal or repeated opening haptic. Drag the handle downward or use Close history to dismiss.
5. Open history by tapping the hint and with VoiceOver. Play a Note, then another: only the second plays. Close history: audio stops. Open a Note's details: the inline player stops. Start capture after playback: capture takes audio-session ownership.
6. Inspect long titles, failed and recovered Notes, and expired local audio. Expect readable title/date/time, duration/source/status, reachable Retry/review/detail actions, and disabled playback when audio is unavailable. Playback or review alone must never send a recovered Note.
7. Enable the largest accessibility text size. Expect stacked card metadata and player, full spoken titles, readable status, and usable controls. Enable Reduce Motion: no decorative continuous motion. Enable Reduce Transparency: opaque dark surfaces with readable boundaries and text.
8. On iOS 18 inspect the material fallback; on a system with native Liquid Glass inspect the native controls and cards. Both retain the same actions and monochrome appearance, except for the red Delete icon in Note detail. Record OS/device versions and visual evidence with acceptance results.

## Input-driven waveform capture regression

Status: pending physical iPhone execution. Tone means measured tonal brightness,
not an exact musical pitch tracker.

1. On a physical iPhone, confirm the idle home shows the logo waveform: flat
   lead-in and lead-out, the logo's curve and floating dot, and a stroke heavy
   enough to read as the app mark. It must not animate while idle.
2. Tap Record in a quiet room. Expect an immediately flat line that stays flat
   through room tone, keyboard noise and distant sound, and that reacts as soon
   as somebody speaks at a normal distance. Stop and repeat: it starts flat again.
3. Watch the start and the end of a Recording Session. Expect the logo mark to
   travel into the recording line and back, not to disappear and be replaced.
   Repeat with Reduce Motion: the states change without animation.
4. Record steady, low and high vowels at similar volume, then vary loudness at
   steady pitch. Expect a waveform trace of the voice rather than the logo mark:
   loudness raises and lowers it and a brighter voice changes which crests stand
   tallest, always vertically, never sliding sideways. Let elapsed time advance
   without changing input: no phase drift.
5. Stop and play the Note, including after a short sound followed by silence.
   Verify audible audio, correct duration, and retention of meaningful short Notes.
6. Repeat after playback, after an interruption, and after a microphone route
   change (wired/Bluetooth input when available). Captured audio must be finalized
   through the existing interruption flow; another Recording Session must start.
7. Discard during capture, then start again. Verify no old audio or tone leaks
   into the next Recording Session. Repeat with Reduce Motion.

Closest deterministic coverage: WhimCore LiveWaveform tests cover the resting logo curve,
the flat line below speaking loudness, the voice trace that replaces the mark
while somebody speaks, and the travel between the two;
RecordingSignal tests use known frequencies, gains, buffer phases and out-of-band
rumble and hiss; PCMRecorderHardware integration tests feed raw PCM through
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

## Liquid Glass capture transition (OS 26 and later)

1. From idle, tap Record. Expect the capture glass to remain visually continuous as its symbol becomes Stop, while a red Discard glass pill emerges directly below it. It must not fade in as an unrelated control or merge with Settings.
2. Tap Discard once. Expect capture to end immediately and the pill to merge back into the capture control. Repeat rapidly, then Stop; no leftover or duplicate controls may intercept taps.
3. Enable Reduce Motion. Repeat: controls change without the morph animation. Enable Reduce Transparency: controls remain legible with opaque surfaces.
4. Verify the existing large hit targets and VoiceOver labels. On pre-26 systems, retain the existing material capture button and plain red Discard without morphing.
5. Record a slow-motion screen capture on physical OS 26 hardware for the visual transition; automated journeys cover the resulting state and operable controls.

## Capture-first startup and actionable failures

Companion availability regression (2026-09-20): the physical iPhone's maintenance
catch received `WCErrorDomain` code 7006, “Watch app is not installed.” The session
was activated and paired, but reported `isWatchAppInstalled == false`; CoreDevice
independently listed `app.whim.ios.watchkitapp` on the Watch. This proves a companion
recognition mismatch, not missing local Notes. Its underlying OS/install cause is
not yet established. No app data was erased during diagnosis.

Verify standalone iPhone startup with a configured webhook shows no recovery error
when no Watch companion is available. Repeat with a paired Watch whose companion
is unrecognized. Record, browse, and play local Notes. When the companion becomes
available, verify queued metadata and configuration synchronize without restarting
Whim. Repeat with the recognized Watch temporarily offline: durable synchronization
must remain queued without requiring immediate reachability. The automated
`testActivatedSessionWithoutCompanionDefersSyncUntilCompanionIsAvailable` covers
deferral and replay across restart; physical post-fix verification remains pending.

Compare cold and warm launches with empty storage and a populated history, including playable crash remnants. Record time to the first onboarding/capture frame separately from time to microphone onset; do not infer capture readiness from the shell alone. Verify Record and Stop remain responsive while old Notes recover or synchronization is offline. Speak immediately after the recording indication and confirm the beginning is preserved.

Deny microphone permission: verify the upper-half glass container explains the issue and Open Settings reaches Whim's permissions. Grant permission and return: the error clears and Record works. Repeat with Reduce Transparency, an earlier supported OS material fallback, VoiceOver, and the largest text sizes; verify the message can scroll and actions/Stop/Discard remain reachable. For storage exhaustion, verify storage guidance and Check again after freeing space. Record physical-device timing evidence; simulator fixtures do not measure real microphone onset.

Compact errors: verify the glass card fits its message without an empty scrolling area or a separate action row. Tapping anywhere on the card runs its recovery action; repeated taps during work are disabled.


## Collapsible recording-screen errors

Status: pending physical iPhone execution.

Deny microphone access, then swipe the error card upward. Verify it becomes a
warning-triangle button with count 1 in the top-left corner, without opening
history or Settings. Tap it to restore the full message, then tap the message
to open Settings. Grant access and return; the card and warning button disappear.
Collapsing must visibly shrink the card into the top-left warning button, and
reopening must grow the card back out of it; with Reduce Motion both switch
without movement.
Repeat with VoiceOver's Collapse notifications action, large Dynamic Type,
Reduce Motion, Reduce Transparency, and the iOS 18 material fallback. For a
failure during capture, verify collapse/reopen leaves Stop and Discard usable.

Closest deterministic coverage: IPhoneModel integration tests cover collapse,
error counts, recovery preservation and resolution; the onboarding iPhone E2E
journey covers upward swipe, the warning button and reopening the recovery card.

## Categorized settings

Status: pending physical-device execution.

1. Open Settings. Verify Webhook, Audio retention, On-device titles, Permissions,
   Apple Watch, and Reset have distinct rounded cards, readable headings and icons.
2. On iOS 26 or later, inspect native Liquid Glass. On iOS 18, inspect the material
   fallback. Enable Reduce Transparency: expect opaque, clearly bounded cards.
3. Enable the largest accessibility text size and VoiceOver. Navigate by headings,
   edit webhook and language fields, and reach every retention choice and Reset.
   Expect wrapping labels, no clipped controls, and a spoken selected retention
   choice. Verify the checkmark and contrast also identify the selected choice.
4. Change retention, leave Settings and reopen it. Verify the selection persists.
   Cancel Reset and verify settings remain; confirm Reset only with disposable data.

Closest deterministic coverage: `e2e/iphone/settings-and-reset.e2e.test.yaml` checks
category headings, configures and tests a webhook, changes retention and exercises
both reset cancellation and confirmation through the installed application.

Simulator verification, 2026-09-22: the settings-and-reset Maestro journey passed
on a fresh iPhone 17 Pro simulator running iOS 27. Screenshots were inspected for
category card boundaries, heading hierarchy, field layout, and section spacing.
This does not establish physical-device, VoiceOver, largest Dynamic Type, Reduce
Transparency, or iOS 18 fallback acceptance. The initial aggregate run was blocked by
`testScheduledAttemptPublishesSendingBeforeTransportCompletes` waiting indefinitely.
On 2026-09-23, a fresh `NSUnbufferedIO=YES npm run test:all` completed successfully,
including all ten iPhone E2E flows and Watch E2E. No delivery-code change was needed.
The earlier stall was not reproduced; its cause remains unconfirmed. Physical
acceptance cases above remain pending.

## Guided onboarding

Status: pending physical-device execution. Use a fresh install or Reset Whim
with disposable data.

1. Inspect the welcome: black background, the still Whim waveform, local storage
   and direct webhook delivery explained, three-step progress, and a prominent
   Get started button. Startup must retain the same welcome layout while loading.
2. Proceed to webhook setup. Only the destination is required; expand
   Authentication & headers to edit optional credentials. Save and test a
   controlled destination, continue, and use Back to revisit it. Repeat using Skip.
3. Verify microphone guidance appears at the permission step. Grant access and
   reach capture; repeat with denied access and Continue without microphone.
   Open system settings, grant access, and return. No speech or notification
   permission prompt appears during onboarding.
4. Repeat with VoiceOver and the largest Dynamic Type size on a small iPhone.
   Verify headings and step progress are announced, Back and every form field
   remain reachable, and the keyboard does not cover the active field or actions.
   While the keyboard is open, tap Continue to microphone and verify it advances
   immediately. Maestro's cached iOS hierarchy can retain pre-keyboard button
   coordinates, so the automated draft-preservation journey uses the explicit
   Done control before this action; it does not establish keyboard-open hit testing.
5. Repeat with Reduce Motion and Reduce Transparency, and on iOS 18. Expect
   still artwork, no transition animation with Reduce Motion, readable opaque
   surfaces with Reduce Transparency, and the native material fallback on iOS 18.

Closest deterministic coverage: the installed onboarding Maestro journeys cover
step progress, Back, optional webhook fields, saved configuration, webhook tests,
and granted/denied completion. Permission commands and persistence are also
covered through the native presentation integration seam. VoiceOver focus,
haptic perception, and physical keyboard/layout acceptance remain manual.

Simulator visual review, 2026-10-04: inspected all three pages on an iPhone 17 Pro
running iOS 27 at normal and maximum accessibility text sizes. The progress header
stays on one line, primary and secondary action labels wrap without truncation,
and privacy copy moves into the scrolling content at accessibility sizes. The
physical-device cases above remain pending.
