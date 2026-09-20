# SwiftUI migration verification

## Coverage migration

The iPhone no longer crosses a JSON/Expo bridge. Native presentation tests live beside their implementations and run through the root Swift package. WhimCore's SQLite, recording, delivery, recovery, permissions, retention, webhook and synchronization suites remain unchanged except for the public HeaderPatch initializer.

| Previous coverage | Native replacement |
| --- | --- |
| TypeScript bridge command/JSON schema tests | Typed WhimClient calls; existing WhimCore contract/projection tests |
| Provider startup, recording, reset and event refresh | IPhoneModel.integration.test.swift, real WhimService and isolated SQLite/audio |
| Timeline formatting and screen actions | TimelineFormat.test.swift and iPhone Maestro journeys |
| Recorder start/stop/discard and confirmations | IPhoneModel integration plus record-and-review Maestro |
| Note detail and playback | NoteDetailModel integration plus record/review and recovered-review Maestro |
| Webhook patch preservation and errors | WebhookEditor integration and WhimCore patch/configuration tests |
| Router/onboarding/settings flows | Existing iPhone Maestro flows, directly launching the native app; cold Settings/Note links |
| Watch screens/synchronization | Existing Watch XCTest and cross-device suites |
| Persisted upgrade | Archived fc1e542 fixture reopened through current native SQLite/preferences/onboarding and service interfaces |
| Tooling | Node tests, including native Swift source-list colocation validation |

## Build baseline limitation

The pre-migration JavaScript and core Swift suites passed after dependency installation. The Expo simulator build exhausted available disk space while compiling Pods; no complete baseline screenshot set or old-to-new installed-app upgrade run was captured. Only this worktree's generated Pods/build caches were removed. Native source layouts, accessibility labels and existing installed-app journeys serve as the migration reference. This limitation must not be presented as a verified pixel comparison or an installed upgrade test.

## Physical acceptance

Use e2e/physical/iphone-presentation.e2e.test.md and the Watch acceptance procedures for real microphone capture, background behavior, accessibility/haptics, locked-device Keychain access and paired-device operation. Existing bundle IDs, app-group identifiers, credential services, persistence filenames and preference keys are retained. The legacy fixture generated from commit fc1e542 is reopened with the current native SQLite, preferences and onboarding stores; tests verify pending/delivered Notes, audio playback, settings and credential projections. The Keychain boundary uses literal fixture credentials. Device installation upgrade and actual Keychain continuity still require physical acceptance.

## Migration review

An independent review identified capture blocking during slow Retry and loss of modal confirmation isolation. Both have regressions and fixes: a suspended HTTP boundary no longer blocks recording, and the installed-app journey verifies background recording controls are inaccessible while confirmation is open. Deterministic boundary gates also cover stale snapshots after Reset, observation restart, overlapping detail lookup/deletion and disappearing audio.

Cold Settings and Note links are covered by a terminated-app journey, including the simulator's system Open confirmation. Incoming URLs are retained at the stable app container while native service construction completes. Permission refresh clears resolved errors; capture feedback and errors post VoiceOver announcements.

A minor review observation remains: toggling Secret header for a header not yet added does not clear an existing webhook-test result. Adding or editing actual configuration clears it; the toggle alone does not alter saved configuration.

## Implementation decisions

- Presentation models and their tests use a root Swift package, with SwiftUI views in the Xcode app target. SwiftPM cannot reference sources outside its package root; keeping this separate from WhimCore avoids moving presentation into the domain package. Installed views are covered by Maestro rather than duplicate hosted model targets. The tradeoff is that package tests alone do not prove UIKit/SwiftUI lifecycle behavior.
- `HeaderPatch` gains a public initializer for typed native callers. Its fields and persistence semantics are unchanged; the cost is a small public API addition.
- The iPhone E2E runner generates ten seconds of fixture audio so Maestro can observe real playback before it finishes. The production webhook test fixture remains unchanged. The longer fixture adds test time and does not validate real microphone capture.
- The old Expo build ran out of disk while compiling Pods. Source layout/copy and existing journeys were used as references; pixel parity and an installed old-to-new upgrade remain unverified. An actual archived database/preferences fixture provides deterministic persistence compatibility coverage.
- Stale permission errors and missing VoiceOver feedback were treated as behavior regressions during review and fixed. Announcements still need physical VoiceOver acceptance; simulator model tests establish the underlying feedback state.
- The native app switch and tooling removal are delivered as one coherent migration commit. The individual red/green slices were exercised during implementation, but were not committed separately; this makes selective rollback less granular.

## Final verification — 2026-09-19

`npm run test:all` completed with exit status 0 on the final production/test sources:

| Suite | Result |
| --- | --- |
| Test colocation | Passed |
| Node tooling/webhook | 18 passed |
| WhimCore unit | 90 passed |
| iPhone presentation unit | 3 passed |
| WhimCore integration | 87 passed |
| iPhone presentation integration (including legacy fixture) | 17 passed |
| Watch model integration | 10 passed |
| iPhone installed-app Maestro | 8/8 flows passed |
| Watch/peer installed-app XCTest | 10 passed |

The aggregate log is `/tmp/whim-swiftui-verified.log`; installed-app results are under the local Maestro and Xcode result directories. Tests used the dedicated iOS 27/watchOS 27 simulators. Supported deployment minimums remain iOS 18/watchOS 11; these older runtimes were not available for this run.

Clean unsigned Release builds succeeded for both `Whim` with `generic/platform=iOS` and `WhimWatch` with `generic/platform=watchOS`, using a fresh `ios/build/ReleaseVerification` directory. `otool -L`/`strings` audits of the iPhone and embedded Watch binaries found no Expo, React Native, Hermes or Pods dependencies and no debug fixture switches. The project generator was run twice with identical resulting project files. `git diff --check` passed; active source/build references to the retired runtime were absent.

Native onboarding screenshots were inspected in Light Mode, Dark Mode and the largest accessibility text size. Text reflows in the scroll view. This was a limited visual sanity check, not the unavailable old/new screenshot comparison or complete accessibility acceptance.

## Native history regression acceptance (2026-09-20)

Automated history coverage checks the close action inside the native navigation
bar, upward/tap entry, list scrolling, downward dismissal, and reopening. The
record-and-review journey covers playback, detail navigation, nested deletion
confirmation, returning to history, and toolbar dismissal. Presentation-model
integration coverage checks that closing history stops playback and external
recording closes history.

On a physical iPhone (iOS 18 and the current iOS release), with contextual
permission prompts still pending behind history:

- Slowly drag down, pause, then release beyond the dismissal threshold. The
  sheet must continue downward without jumping upward, fading in place, or
  flashing the underlying permission prompt over its content.
- Make a short downward drag and cancel it. The sheet must settle smoothly;
  the selected filter, list position, and active player must remain unchanged.
- Repeat opening and closing by gesture and toolbar; verify one opening haptic,
  no hidden playback after dismissal, and no duplicate modal presentation.
- Repeat with Reduce Motion and Reduce Transparency, VoiceOver, and the largest
  accessibility text size. Close remains reachable inside the modal toolbar.

Frame-level animation quality and physical haptics remain manual acceptance;
Maestro checks accessibility-visible outcomes rather than every rendered frame.

### Verification results

Verified on 2026-09-20 using the iOS 27 and watchOS 27 simulators:

- `npm run test:all` completed tooling/Swift unit tests and host/simulator
  integration tests successfully. The first E2E attempt ran out of disk space
  during app reinstallation; temporary simulator/build artifacts were removed.
- The aggregate rerun passed eight iPhone journeys. The retry journey exposed
  an obsolete `Back` text selector: native navigation now labels that button
  `Previous notes`. Updating the test to the native `BackButton` identifier and
  rerunning `failed-and-retry.e2e.test.yaml` passed, completing all nine journeys.
- `npm run test:e2e:watch` passed separately after the iPhone reruns.
- Before/after simulator recordings reproduced the old release jump and fade,
  then showed continuous native downward dismissal. The native toolbar and
  compiled waveform app icon were visually inspected. `git diff --check` passed.

An additional iOS 18 simulator run was deferred due to disk pressure. Physical
motion, haptics, and the accessibility acceptance cases above remain pending.
