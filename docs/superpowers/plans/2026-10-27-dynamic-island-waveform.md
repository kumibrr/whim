# Dynamic Island waveform implementation plan

> Implement inline as vertical test-driven slices.

**Goal:** Display the voice waveform in every Dynamic Island size and stop the Recording Session by tapping the expanded content.

**Architecture:** RecordingService forwards measured power and tone through RecordingActivityManaging to LiveActivityAdapter and ActivityKit. The widget draws the shared LiveWaveform geometry directly from activity content; widget rendering must not depend on onAppear or local animation state.

**Tech stack:** Swift 6, SwiftUI, ActivityKit, XCTest, existing root test scripts.

**Spec:** User request plus `docs/superpowers/specs/2026-09-04-whim-v1-design.md`.

## Constraints and review focus

- Preserve canonical session identity, start time, stop/save behavior, iOS 18 support, accessibility, and existing Lock Screen Stop.
- Ignore measurements for absent sessions; never recreate an ended activity from a late measurement.
- Bound ActivityKit publication frequency while forwarding measured power and tone, including silence.
- ActivityKit controls display timing; responsiveness and expanded hit coverage require physical acceptance.
- Compact/minimal taps retain iOS's app-opening behavior; the expanded content is a single accessible Stop button.

## Task 1: Recording signal to Live Activity

- [x] Add a failing integration test using real RecordingService + LiveActivityAdapter and a recording-system boundary fixture. Assert signal power/tone reach only the active session; retain the existing legacy peak-power projection coverage.
- [x] Extend the two activity seams with `update(sessionID:signal:)`; add tested bounded publication and session filtering in LiveActivityAdapter.
- [x] Add Codable content carrying the original startedAt, measured power, and tone, with safe initial silence. ActivityKit updates retain start time and stale date.
- [x] Run affected unit/integration tests.

## Task 2: Widget presentation and interaction

- [x] Add failing system-surface rendering tests proving measured power/tone change the waveform immediately without view lifecycle callbacks.
- [x] Share a stateless waveform renderer with the app waveform; expanded content is a full-width plain Stop-intent button, compact leading is elapsed duration, compact trailing and minimal are small waveforms.
- [x] Execute the actual expanded button's Stop action against real owned modules and assert one finalized Note and no active Recording Session.
- [x] Record hardware checks for all sizes, corner taps, silence/speech, VoiceOver, and Reduce Motion.

## Task 3: Verification

- [x] Run `npm run test:all` and review all failures.
- [x] Review the complete diff and verify the rebuilt iOS app through system-surface tests.

## Review and verification record

- Core regression: microphone publication failed with an empty measurement list before implementation; targeted activity/content/recording tests pass afterward.
- UI tests initially failed because the new snapshot view and expanded control did not exist. Both new tests passed in WhimSystemSurfaceTests on the iPhone 18 Pro simulator (iOS 27).
- Read-only review found ActivityKit publication could block the recorder event loop. A gated-system test reproduced both Stop and interruption timeouts, then passed after publication moved to one worker with a newest-only pending sample.
- Hardware refresh cadence, system-owned hit coverage, and physical accessibility remain DI-1 acceptance cases; automatic tests cannot prove them.
- Build caches are on the external SSD after the internal disk filled during the first Xcode run. The interrupted generated build state was set aside and rebuilt.

- Full-run limitations: the first complete attempt reached Watch tests after passing 75 tooling tests, 128 core unit tests, all iPhone unit tests, 148 core integration tests, 49 iPhone integration tests, system-surface tests, and native audio tests. The shared Watch simulator had a missing test-manager socket.
- A rerun hit `scripts/release.test.mjs` / `concurrent edits to unrelated.txt during validation stop publication` during fixture version preparation; the same test passed in isolation afterward.
- Independent integration verification repeated the passing core, iPhone, widget, and audio checks. A replacement Watch ran 15 tests; `testEventRefreshFailureIsVisibleAndLaterEventClearsIt` failed with SQLite error 5 (database is locked). No Watch persistence or release-tooling code was changed.

- Identical microphone measurements now avoid repeated ActivityKit publication. The companion test first observed duplicate updates, then passed after deduplication; a changed measurement still publishes and the system timer advances independently.
- Final `npm run test:unit:swift` passes (129 core tests and 3 iPhone tests). Targeted activity/content/recording integration tests pass after deduplication.
- The installed Live Activity E2E initially missed Stop, and a timing-only probe did not resolve it; no probe changes remain in the E2E flow. A later run could not find the Live Activity. A controlled comparison using the original widget and original ActivityKit request/end behavior (with no meter publication) reproduced that same visibility failure. The feature sources were restored and checked against their saved contents afterward. System-surface rendering and direct Stop-intent tests provide the deterministic coverage; real-device DI-1 acceptance remains pending.
- The broad E2E attempt passed `history-sheet.e2e.test`; it was then stopped to focus on the affected Live Activity journey after the unrelated broad-suite failures. The full E2E suite and physical acceptance are not claimed green.

- Final feature rebuild: `scripts/test-system-surfaces.sh` passed; all 7 cases passed, including measured voice rendering at every Island size and the expanded waveform's Stop/save action. App/extension embedding, App Groups, Live Activity support, and shortcut metadata passed their built-contract checks. Test colocation and `git diff --check` passed. The final app artifact contains the feature implementation, not the temporary baseline comparison.

## Expanded controls follow-up — 2026-10-28

- Place the elapsed recording duration, still red, in the expanded Island's upper-left leading region. Its tap invokes the same Stop intent.
- Center the app's 24-point rounded red square over the waveform. Preserve the full waveform hit area and existing Stop/save semantics.
- The native rendering regression reproduced the absent central Stop affordance before implementation. Existing real-facade Stop/save coverage remains in the affected system-surface suite. DI-1 now includes the timer, centered square, and their tap positions.
- Verification: the updated native app/test bundle compiled. The initial regression run exercised all 8 system-surface cases and failed on the missing centered red control as intended. After implementation, an existing waveform PNG rendering case stalled with IOSurface/image-provider timeouts. Xcode also reported a CoreSimulator service version mismatch during this session. Focused retries stalled in build/installation; remaining owned verification processes were stopped. `test:all` passed all 75 tooling tests, then stalled in Swift test startup and was stopped. Runtime green verification and hardware DI-1 remain pending; `git diff --check` passes.

### Circular Stop surround and legible duration

- Restored the app's 80-point circular surround around the 24-point Stop square, with a dark fill and fine outline that stay visible in activity snapshots. The whole waveform remains the same Stop action.
- Expanded duration uses the system title2 semibold style (22 points at the default iOS size); compact duration uses subheadline semibold. These are implementation choices following Apple's guidance to use larger text at medium weight or heavier, rather than Apple-mandated point sizes: https://developer.apple.com/design/human-interface-guidelines/live-activities
- Updated the companion rendering regression to assert a visible circular surround on black. Its matching native SwiftUI rendering check failed before implementation (inside pixel 0), then passed after implementation. The delivered preview uses the real expanded content, a fixture timer value, and iOS-equivalent 22-point text on the macOS preview host; it is not a device screenshot.
- This follow-up's `test:all` attempt stalled while booting the shared CI iPhone before reaching the suites; the owned verification process was stopped. The SwiftUI circular-surround check, preview render, test-colocation check, and whitespace check passed. iOS system-surface and full-suite green status remain unverified.

### Translucency and duration insets

- The circular surround now uses 12% white, allowing the waveform/background to show through while keeping the red Stop square opaque. Added 12 points of leading inset and 8 points of top inset to the expanded duration.
- Updated the companion render regression to use a blue backdrop and verify that the circle transmits that backdrop. The matching SwiftUI check reproduced the opaque-circle bug before implementation (blue channel 31); the updated preview uses the real expanded content and the same duration insets.
- Validation: the translucent-circle SwiftUI regression passes, the new padded preview renders, and test colocation/whitespace checks pass. `test:all` passed all 75 tooling tests, 129 core unit tests, 3 iPhone unit tests, and 4 webhook integration tests. Its core integration process then stopped producing output for roughly five minutes at 0% CPU; the last complete logged case was `testOnboardingCompletionPersistsAndResetClearsLocalLifecycle` (passed). A process sample showed XCTest waiting for async completion. The owned full run was stopped and its log/sample preserved under `/tmp/whim-island-translucent-all.log` and `/tmp/whim-island-integration-hang.txt`. The separate widget run was stopped to avoid competing with the full run for shared Swift package caches. Full-suite/iOS runtime green verification is not claimed.
