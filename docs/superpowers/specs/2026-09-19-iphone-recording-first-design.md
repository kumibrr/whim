# Whim iPhone recording-first design

**Date:** 2026-09-19

**Status:** Approved. Written specification approved on 2026-09-19.

## Intent and scope

Make iPhone capture feel immediate and visually quiet: a sober black screen,
white accents, an audio-reactive central line, and glass controls. Previous
Notes live in a gesture-driven sheet with inline playback.

This design supersedes the v1 specification's timeline-first iPhone home,
system Light/Dark appearance, and coral recording accent. It preserves the
v1 domain model, recording/finalization rules, delivery behavior, retention,
onboarding, settings capabilities, and accessibility requirements. Watch UI
and behavior are unchanged. The minimum iPhone deployment version remains
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

A plain, thin white horizontal line spans the center of the screen. It does
not animate while idle. A circular glass Record button sits at bottom center,
above the safe area. A glass settings button sits at top right and contains
only the settings icon visually; its accessibility label is Settings.

Below Record, a small tappable hint reads exactly:
"scroll to see previous notes."

### Active Recording Session

Record starts capture through the existing command. The full-width line
reacts to microphone input in real time. Speech increases its amplitude;
silence settles it toward a plain line. It never progressively fills the
screen and is not a left-to-right history of elapsed audio. Rendering may
smooth between measured levels, but must not invent activity during silence.

Only Stop and Discard are available. Hide settings and the history hint,
disable the history gesture, and close any presentation that would expose
other actions if recording starts from an external entry point. Show elapsed
time, five-minute progress, and the existing approaching-limit warning without
competing visually with the waveform. Keep start/stop feedback.

Stop saves and starts the existing workflow. After successful finalization,
return to idle with the plain line. Do not automatically open history.
Discard retains the existing confirmation and Keep recording escape action.
No pause/resume recording is introduced.

Pending commands prevent duplicate actions. A failed command preserves the
actual Recording Session state and exposes a readable error. Interruptions,
automatic duration-limit finalization, and recovery retain v1 behavior.

## History sheet

An upward drag from idle progressively reveals a bottom sheet that follows
the finger. Releasing beyond its opening threshold settles it into the open
position; otherwise it returns to idle. Use one soft haptic when the sheet
commits to opening, not on every drag update or a canceled drag. Tapping the
hint opens the same sheet and supplies an accessible alternative gesture.

The sheet can expand for browsing and dismiss downward. Once open, its list
scrolls normally; dragging a scrolled list must not unexpectedly dismiss it.
Respect safe areas and system accessibility navigation. Reduced Motion uses
restrained transitions while retaining direct manipulation.

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
SwiftUI owns layout and transient sheet drag geometry.

- Refactor `IPhoneRootView` to compose an idle/active capture surface and the
  history presentation, retaining onboarding, links, permissions, and errors.
- Reuse recorder commands and native recording-progress events. The current
  peak-power projection drives the live visual envelope; no new microphone
  capture path or persisted live sample buffer is required.
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
