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
