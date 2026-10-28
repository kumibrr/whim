# Action button stop and send implementation plan

**Goal:** The existing iPhone “Record a Whim” shortcut starts capture when idle and stops, saves, and starts delivery when already recording.

**Architecture:** Keep the behavior in `RecordWhimIntent`, shared by the Action button, Siri, and Lock Screen control. Reuse `CaptureEntryService.stop()` and the existing WhimService workflow. Keep Watch launch/focus behavior and direct `startRecording` semantics intact.

**Decision:** The user chose to change the existing shortcut rather than add a separate Action button shortcut. This supersedes the v1 specification's previous repeated-iPhone-invocation rule.

## Slice

- [x] Update the real intent/control companion tests; observe failures for an active recording remaining active and no Note being saved.
- [x] On iPhone, check for active capture and use normal Stop before attempting Record. Verify online delivery, offline queuing, missing configuration, and a subsequent new Recording Session.
- [x] Add installed-app coverage using a DEBUG fixture-only link that executes the production intent with the shared runtime; retain the existing Live Activity Stop journey.
- [x] Update the canonical v1 behavior and physical acceptance cases for locked/unlocked repeat presses and alternating entry points.
- [x] Run system-surface tests, the affected installed journey, and root `npm run test:all`; review the diff and report any unverified hardware behavior.

## Verification evidence

- System surfaces: the three changed/new tests failed on the original implementation because capture remained active and no Note existed; all seven tests passed after the intent change. Built extension/shortcut metadata verification passed.
- Installed journey: first failed without the fixture link handler, then exposed an App Intents dependency assertion when calling the intent outside system dispatch. The handler now explicitly injects `WhimRuntime.shared`, as the native companion tests do with their fixture runtime.
- The complete installed journey then passed: start, repeat to stop, Sent from the loopback webhook, playback, and a third invocation starting a fresh session. `npm run test:unit` passed (75 tooling, 124 core, and 3 iPhone unit tests).
- Independent read-only review found no actionable issues. Physical dispatch, locked execution, and real microphone behavior remain acceptance cases.
- Final `npm run test:all` exited 0: tooling, Swift unit, core/iPhone/platform/Watch integration, all 19 iPhone E2E journeys, and Watch E2E passed. `git diff --check` passed. Physical Action-button and locked-device acceptance remain pending in the updated procedure.
- Environment: initial builds exhausted internal disk space, then a shared CI simulator lost its test-runner connection. Generated build files were moved to the external SSD; subsequent runs use a separate simulator pair and the environment in `/tmp/whim-action-env.sh`.
