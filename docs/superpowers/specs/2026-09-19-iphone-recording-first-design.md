# Whim iPhone recording-first design

**Date:** 2026-09-19

**Status:** Implemented on 2026-09-19. Automated verification passed; physical acceptance remains pending.

## Intent and scope

Make iPhone capture feel immediate and visually quiet: a sober black screen,
white accents, an audio-reactive central line, and glass controls. Previous
Notes live in a gesture-driven sheet with inline playback.

This design supersedes the v1 specification's timeline-first iPhone home,
system Light/Dark appearance, and coral recording accent. It preserves the
v1 domain model, recording/finalization rules, delivery behavior, retention,
onboarding, settings capabilities, and accessibility requirements. Watch UI
and behavior are unchanged, except that the Watch capture screen shares the
logo waveform described below. The minimum iPhone deployment version remains
iOS 18.

## Visual system

- Use a black background, white primary text and accents, and subdued gray
  secondary text. Do not add a colored glow or decorative background motion.
- Use native typography, generous empty space, and subtle glass highlights.
- Record, Stop, settings, and history cards use rounded glass surfaces.
  Use native Liquid Glass where supported and a consistent translucent
  material fallback on older supported systems.
- Keep status text and symbols readable. Failures and destructive actions
  must remain distinguishable without depending on color.
- Apply the monochrome appearance consistently to iPhone sheets and settings.
  Reduce Transparency uses more opaque surfaces with sufficient contrast.

## Home and recording states

### Idle

The Whim logo waveform spans the center of the screen: a heavy white stroke
that runs in flat from both edges, through the logo's voice-shaped curve and
its floating dot. Stroke weight and height follow the logo's proportions. It
does not animate while idle. A circular glass Record button sits at bottom center,
above the safe area. A glass settings button sits at top right and contains
only the settings icon visually; its accessibility label is Settings.

Below Record, a small tappable hint reads exactly:
"scroll to see previous notes."

### Active Recording Session

Record starts capture through the existing command. One waveform serves both
states: starting a Recording Session animates the mark into the recording line
rather than swapping one drawing for another, and ending one animates it back.
Capture begins as a flat line and stays flat until somebody speaks. Speech then
draws a waveform trace of the voice, not the logo mark. Amplitude spans the
loudness of a human voice near the device, so a quiet room reads as silence
rather than as a moving line. The trace never progressively fills the screen and
is not a left-to-right history of elapsed audio. Rendering may smooth between
measured levels, but must not invent activity during silence. It holds still for
steady input. Volume scales amplitude; measured tonal brightness redistributes
the heights of its crests. The trace only ever moves vertically: its crossings
never slide sideways. Brightness is measured across the human voice band, so
rumble below it and hiss above it do not steer the shape. Smooth only the
transitions between changed measurements and between the two states, with no
clock-driven phase, perpetual animation, or random motion. Both edges taper
toward almost zero. Silence settles to a flat line.
Reduce Motion applies measurement and state changes without animated
interpolation.

The Watch capture screen uses the same waveform, geometry and transitions,
scaled to its width. WhimCore owns the shared waveform so both devices draw
one mark. The Watch keeps AVAudioRecorder, which measures loudness but not
tonal brightness, so its voice trace scales with volume while its crest
heights keep their neutral shape until a tone measurement is available.

Only Stop and Discard are available. Hide settings and the history hint,
disable the history gesture, and close any presentation that would expose
other actions if recording starts from an external entry point. Show elapsed
time, five-minute progress, and the existing approaching-limit warning without
competing visually with the waveform. Keep start/stop feedback.

Stop saves and starts the existing workflow. After successful finalization,
return to idle with the resting logo curve. Do not automatically open history.
Discard immediately ends and removes the Recording Session without confirmation. The red button has a minimum 120 × 56 point tappable area. On iOS 26 and later, its glass capsule morphs out of the Record/Stop glass control using a shared Liquid Glass container and namespace. Reduce Motion disables the morph; older systems retain the plain red button.
No pause/resume recording is introduced.

Recording-screen errors initially appear as full glass cards. An upward swipe
collapses the card without clearing its failure or opening history. A glass
warning-triangle button at the top left shows the number of active errors;
tapping it restores the highest-priority error and its recovery action. The
button is also available during an active Recording Session. Resolved errors
leave the count, and the button disappears when none remain. A new issue
reopens the card. VoiceOver offers a Collapse notifications action. History
and settings retain their expanded recovery presentation.


Pending commands prevent duplicate actions. A failed command preserves the
actual Recording Session state and exposes a readable error. Interruptions,
automatic duration-limit finalization, and recovery retain v1 behavior.

## History sheet

Updated 2026-09-20: an upward drag from idle past the opening threshold or
an accessible tap on the hint presents a native SwiftUI sheet. Use one soft
haptic when opening commits. iOS owns presentation, interactive downward
dismissal, cancellation, safe areas, and Reduce Motion transitions. Do not
simulate a sheet with offsets, conditional removal, or a second drag animation.

History has its own NavigationStack inside the sheet. Put its title and Close
button in that stack's native navigation toolbar; Note detail pushes within
the same sheet. The history list scrolls normally. Closing the sheet by toolbar
or gesture stops inline playback. Keep the underlying capture surface stable
through the entire transition, including contextual permission prompts.

Keep newest-first order and All, Queued, Failed, and Sent filters. Preserve
empty, loading, and error states. Failed Notes remain chronological and
visibly actionable; recovered Notes continue to require explicit review and
Send. Opening history never marks a recovered Note as approved for delivery.

## Note cards and playback

Each Note uses a glass card. At ordinary text sizes, the left side contains
a single-line, truncating title and date/time. The adjacent player contains
a play/stop control and a compact waveform with elapsed playback indicated.
Retain duration, source device, delivery/review status, audio availability,
and Retry where applicable in a compact supporting row. Existing Note detail
remains reachable separately from the player and retains delivery details,
review/Send, and Delete.

At accessibility text sizes, stack the metadata and player to preserve
readability and usable controls; expose the full title to VoiceOver.

The saved waveform is derived from the Note's local audio, not random bars.
Only one Note plays at a time. Playing another stops the previous one. Use
the existing play/stop semantics; seeking, trimming, and editing are outside
this change. Starting capture stops playback through the existing service.
Dismissal of history stops its inline playback so idle capture has no hidden
player. Navigating to detail also stops inline playback before transferring
interaction to the existing detail player.

Expired or unavailable audio keeps its metadata card with a clear availability
label and disabled playback. Waveform loading or decoding failure must not
block otherwise playable audio: show a neutral line fallback and preserve
the real playback control. Do not fabricate an audio waveform.

## Architecture and data flow

Keep WhimCore authoritative for Recording Sessions, Notes, delivery, and
playback. The native iPhone presentation model owns observable UI state;
SwiftUI owns layout and the native sheet transition.

- Refactor `IPhoneRootView` to compose an idle/active capture surface and the
  history presentation, retaining onboarding, links, permissions, and errors.
- Reuse recorder commands and native recording-progress events. iPhone capture
  uses one AVAudioEngine input tap to convert to 16 kHz mono PCM, measure volume
  and tonal brightness, and write the existing AAC-LC `.m4a` format. Watch retains
  AVAudioRecorder. Do not persist live samples or analysis metadata.
- Extend recording progress with optional normalized tonal brightness, derived
  from normalized first-difference energy of the same PCM saved to the Note.
  It reflects frequency content, not an exact fundamental-pitch estimate.
  Ignore tiny tone fluctuations in presentation; no measurement depends on time.
  Preserve interruption finalization, startup/discard cleanup, and the maximum
  captured peak used to retain short meaningful Notes.
- Use Apple's streaming AVAudioConverter API for sample-rate conversion
  ([TN3136](https://developer.apple.com/documentation/technotes/tn3136-avaudioconverter-performing-sample-rate-conversions)).
- Extend the typed WhimClient interface with a Note waveform query returning
  bounded normalized amplitude samples and explicit unavailability. Keep
  filesystem paths and audio decoding behind WhimCore and its platform adapter.
- Decode local audio off the main actor in bounded chunks. Cache a bounded
  number of results in memory, keyed by Note identity. Check current audio
  availability before serving cached results; deletion or retention must not
  expose stale available-audio state. Do not persist new metadata or alter
  Watch synchronization for this presentation feature.
- Extend the iPhone presentation model with shared inline playback commands
  and progress using the existing playback snapshot interface. Poll only
  while inline playback is active; cancel on dismissal, completion, navigation,
  or recording. Ignore stale asynchronous results after switching Notes.
- Extract reusable glass styling and waveform drawing so recorder and card
  views remain small. Preserve the existing detail and settings behaviors.

These additions extend the agreed WhimCore, platform adapter, native iPhone
presentation, and installed-application test seams; they do not introduce a
separate source of canonical state.

## Verification

Implement each behavior as a vertical test-driven slice: failing companion
test at its public seam, minimum implementation, then the affected suite.
Use real owned modules together; fake microphone, time, and other system
boundaries only where deterministic control is necessary.

- Verify recording-only action availability, external recording transitions,
  post-stop idle behavior, and failed-command state through presentation and
  installed-app tests at the lowest sufficient seam.
- Verify waveform queries with known audio, silence, unavailable/corrupt audio,
  bounded sample output, and retention/deletion after a cache has been populated.
- Verify inline playback replacement, completion, stale results, dismissal,
  unavailable audio, and capture stopping playback through public interfaces.
- Update iPhone E2E journeys to open history explicitly and cover gesture/tap
  entry, cards, playback, detail, filters, recovery, and recording restrictions.
  Preserve the existing onboarding, permissions, configuration, and error flows.
- Inspect simulator layouts at normal and accessibility text sizes, including
  empty history, long titles, failed/recovered Notes, and expired audio. Verify
  the native glass and older-system fallback on supported runtimes available
  in the environment, recording any coverage limits.
- Add physical acceptance procedures for the sheet-opening haptic, speech
  responsiveness, silence, VoiceOver, Reduce Motion, Reduce Transparency,
  and actual microphone/playback transitions.

Keep root unit, integration, and E2E scripts runnable. Run `test:all` before
declaring implementation complete. Documentation alone does not require
artificial behavior tests.
