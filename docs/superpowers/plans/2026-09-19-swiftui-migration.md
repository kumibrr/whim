# SwiftUI Migration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans or superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox syntax for tracking.

**Goal:** Replace the complete Expo/React Native iPhone app with SwiftUI while preserving current screens, flows, and stored data.

**Architecture:** SwiftUI views use a main-actor observable iPhone presentation model over the existing WhimClient interface. WhimProductionComposition continues constructing native services; iPhone joins Watch in consuming WhimCore through Swift Package Manager. No JavaScript runtime remains in the shipped app.

**Tech Stack:** Swift 6, SwiftUI, Observation, WhimCore/GRDB, XCTest, Maestro, existing Node webhook fixture and shell runners.

**Spec:** `docs/superpowers/specs/2026-09-19-swiftui-migration-design.md` (approved by user).

## Execution record

The native implementation is in place. The original checklist below records the proposed sequence, not an assertion that every baseline or physical check was possible. See [migration verification](../../swiftui-migration-verification.md) for the final evidence, coverage mapping, review fixes and deviations.

Presentation tests use the root Swift package rather than duplicate simulator-hosted targets. The upgrade fixture is colocated with `IPhoneModel.integration.test.swift`. The archived Expo build exhausted disk while compiling Pods, so baseline screenshot comparison and an installed old-to-new upgrade remain acceptance work. Implementation slices are consolidated into one migration commit rather than separate task commits.

## Global constraints

- Keep iOS 18 and watchOS 11 minimums.
- Preserve current screens and flows; use existing TSX, tests, and screenshots as the parity reference.
- Preserve bundle identifiers, app groups, entitlements, database/audio paths, preference keys, and Keychain attributes.
- Mock system boundaries only; compose owned services in integration tests.
- Keep root test:unit, test:integration, test:e2e:iphone, test:e2e:watch, test:e2e, and test:all commands runnable.
- No unrequested redesign, domain rewrite, new v1 feature, telemetry, or runtime dependency.
- Follow CONTEXT.md terminology and the v1 design except where the approved migration spec supersedes Expo architecture/testing.

## Review focus

1. A late snapshot must not undo an event, deletion, reset, or newer refresh (Task 2).
2. Saving unrelated configuration must preserve existing masked credentials and URL query values (Task 5).
3. Opening a Note that is deleted or expires while visible must not leave playable stale audio or crash (Task 4).
4. Upgrading an existing installation must retain settings, pending Notes, audio, and credentials (Task 6).
5. Repeated lifecycle activation or Record taps must not duplicate event subscriptions, services, or recording (Tasks 2–3).

## File structure and interfaces

Keep Swift files beside their corresponding current screen directories under src/iphone. Create:

- app-composition/IPhoneModel.swift: lifecycle, snapshots/events, observable state and commands; companion IPhoneModel.integration.test.swift.
- app-composition/IPhoneError.swift and IPhoneError.test.swift: sanitized domain-error presentation, preserving bridge messages.
- app-composition/IPhoneRootView.swift: navigation and onboarding gating.
- app-composition/WhimIPhoneApp.swift: SwiftUI entry point and service ownership.
- appearance/IPhoneTheme.swift: existing semantic colors, sizing, spacing, coral #CC4939.
- timeline/TimelineView.swift, NoteRowView.swift, TimelineFormat.swift, TimelineFormat.test.swift.
- recording/RecorderView.swift: existing recorder and confirmation interactions.
- onboarding/OnboardingView.swift: existing onboarding steps.
- note-detail/NoteDetailView.swift and NoteDetailModel.swift with NoteDetailModel.integration.test.swift.
- webhook-configuration/WebhookConfigurationView.swift and WebhookEditor.swift with WebhookEditor.integration.test.swift.
- preferences/PreferencesView.swift and destructive-actions/ConfirmationView.swift.
- app-composition/UpgradeCompatibility.integration.test.swift: previous-store compatibility.

IPhoneModel is @MainActor @Observable, initialized with `init(client: any WhimClient)`. Expose `notes: [NoteProjection]`, `recording: RecordingProjection?`, `settings: SettingsProjection?`, `playback: PlaybackProjection?`, `error: IPhoneError?`, `isRefreshing: Bool`, `elapsedSeconds: Double`, and `peakPowerDBFS: Double`. Methods: `start() async`, `stop()`, `refresh() async`, `startRecording() async`, `stopRecording() async`, `discardRecording() async`. Own a single cancellable observation task; wrap the remaining existing WhimClient commands without changing their domain signatures. Keep command failures observable and cancellation separate from user-facing failures.

NoteDetailModel uses `init(client: any WhimClient, noteID: NoteID)`, exposes `note: NoteDetailProjection?`, and implements `refresh() async`, `play() async`, `stopPlayback() async`, `retry() async`, `sendRecovered() async`, and `delete() async`. Subscribe through the root model to refresh visible details; do not create a second production service.

WebhookEditor uses `init(client: any WhimClient)` and native WebhookPatch/SecretPatch values. Expose `isDirty`, `isPending`, result/error text and retry offer; methods `save() async`, `test() async`, `retryUnsent() async`. Form edits clear stale outcomes. Never populate secret text inputs with saved secret values.

Add simulator-hosted WhimIPhoneTests and WhimIPhoneIntegrationTests targets in scripts/configure-xcode-project.rb and the Whim scheme. Keep pure formatting/error unit tests runnable without a simulator by adding a Swift package test target for those Foundation-only sources (explicit source lists and colocation validation). Views stay in the application target. Integration tests link the actual app module and real WhimCore via SPM; no duplicate Pod copy of WhimCore.

## Task 1: Baseline and native test harness

**Files:** scripts/configure-xcode-project.rb, scripts/check-test-colocation.mjs and its companion test, scripts/test-swift.sh, packages/WhimCore/Package.swift, ios/whim.xcodeproj/project.pbxproj, ios/whim.xcodeproj/xcshareddata/xcschemes/Whim.xcscheme; new timeline/TimelineFormat.swift and companion.

- [ ] Run the current aggregate suite and record pre-existing failures; do not attribute them to the migration.

```sh
npm run test:all
```

- [ ] Build/launch the existing application using its runner, capturing baseline home, recorder, detail, onboarding, and settings screens in Light/Dark Mode. Record accessibility identifiers and existing flow assertions; use local build output for screenshots, not source assets.
- [ ] Add unit/integration target routing tests to check-test-colocation.test.mjs. Run `node --test scripts/check-test-colocation.test.mjs` and observe missing native routing fail; implement routing for production, unit, and integration Swift sources.
- [ ] Add the first native formatting test and observe its failure before implementing the formatter:

```swift
func testDurationMatchesCurrentUI() {
    XCTAssertEqual(TimelineFormat.duration(seconds: -1), "0:00")
    XCTAssertEqual(TimelineFormat.duration(seconds: 65.9), "1:05")
}
```

- [ ] Implement `TimelineFormat.duration(seconds: Double) -> String` by clamping at zero, flooring seconds, and formatting minutes plus a two-digit remainder. Preserve existing status copy and localized date display. Register the pure-source test target and root unit runner; keep existing suites during transition.
- [ ] Run `npm run test:unit`; verify new tests execute rather than merely compile. Commit this independently testable harness slice.

## Task 2: Native presentation state and startup

**Files:** app-composition/IPhoneModel.swift, IPhoneModel.integration.test.swift, IPhoneError.swift and companion; existing WhimProvider.test.tsx and ExpoWhimModule.integration.test.swift as behavior references.

- [ ] Create integration fixtures using the existing WhimService integration setup: real WhimService, temporary SQLite/audio store, controlled clock/microphone/transport/permissions. Do not fake the owned client in integration tests.
- [ ] Add failing tests for launch loading, foreground refresh, active recording restoration, settings/reset events, duplicate start, cancellation/restart, sequence gaps and overlapping refresh. Use deterministic boundary gates to delay snapshot work, then issue recording/delete/reset through the real service. Assert final public model state, not private tables or tasks.
- [ ] Run the new tests using `xcodebuild test -workspace ios/Whim.xcworkspace -scheme Whim -only-testing:WhimIPhoneIntegrationTests -destination "id=$WHIM_IPHONE_SIMULATOR_UDID"` and confirm each fails for its missing behavior.
- [ ] Implement one case at a time: subscribe first, load state, fold newer events over stale snapshots, discard stale refresh generations, refresh on gaps/settings/reset, cancel observation and prevent duplicate start. Reuse existing service construction and typed events.
- [ ] Port the bridge's error mapping into IPhoneError with tests covering permission, missing Note, invalid configuration, and generic redaction. Unknown failures display the current generic message, never raw credentials or server response bodies.
- [ ] Run the native integration target and unit suite; commit.

## Task 3: Onboarding, timeline, and recording

**Files:** WhimIPhoneApp.swift, IPhoneRootView.swift, IPhoneTheme.swift, OnboardingView.swift, TimelineView.swift, NoteRowView.swift, RecorderView.swift, ConfirmationView.swift; ios/whim/Info.plist; e2e/iphone/onboarding.e2e.test.yaml and record-and-review.e2e.test.yaml.

- [ ] Add/adjust installed-app assertions for native onboarding gating, existing filter labels, duplicate Record taps, elapsed progress, Stop, and cancel/confirm Discard. Existing missing UI supplies the failing assertions; run them and save the failure evidence.
- [ ] Implement the named screens with the current TSX structure/copy and theme values. Keep dynamic type rather than fixed-height text containers. Preserve accessible IDs such as whim-home, waveform/progress semantics, 48-point minimum existing controls, feedback, and Reduce Motion.
- [ ] Wire a native test-build entry configuration first so Expo remains usable as the baseline until the final switch. One composition instance owns the service, model and lifecycle. Preserve Info.plist permissions and URL scheme; remove only legacy scene settings when switching entry points.
- [ ] After first saved Note, offer optional permissions only when undetermined; cancelled, short/discarded, reset and stale completion events must not show the saved-note prompt. Add deterministic service/model regressions for these paths.
- [ ] Run onboarding and recording Maestro flows against the native configuration, plus affected Swift suites. Compare baseline screenshots; commit.

## Task 4: Note detail, playback, and recovery

**Files:** NoteDetailView.swift, NoteDetailModel.swift and companion; e2e/iphone/record-and-review.e2e.test.yaml, recovered-review.e2e.test.yaml, failed-and-retry.e2e.test.yaml.

- [ ] Add failing integration cases for detail lookup, unavailable audio, playback while recording, deletion while detail is visible, successful retry, and explicit recovered Send. Exercise real service calls and boundary fixture audio.
- [ ] Implement typed NoteID routing, detail refresh, existing metadata and sanitized Attempt destination display, playback actions, Retry and recovered review/Send. Preserve delivered-versus-unsent deletion confirmation. Deleted Notes dismiss or show the existing missing-note state; expired audio cannot still appear playable.
- [ ] Run each case red/green at the integration target. Run the three corresponding installed-app journeys, including cancel and confirm deletion. Commit.

## Task 5: Settings and webhook editing

**Files:** WebhookEditor.swift and companion, WebhookConfigurationView.swift, PreferencesView.swift; e2e/iphone/settings-and-reset.e2e.test.yaml, failed-and-retry.e2e.test.yaml.

- [ ] Add failing real-service integration cases for preserve/replace/clear bearer and HMAC, custom-header removal and retention, unchanged URL with secret query, invalid reserved headers, dirty Test disabled, repeated Save, test success without idempotency echo, failed test, and retry offer count. Inspect requests at the loopback webhook boundary rather than exposing stored secrets to UI assertions.
- [ ] Implement the existing WebhookPatch semantics and exact user-facing outcomes. Retain untouched values, clear outcomes on edits, disable commands while pending and Test while dirty, and show current sanitized destination. Test uses the bundled fixture and does not create timeline history.
- [ ] Port retention options, transcription/language, permission/system-settings routing, Watch synchronization status, and destructive Reset. Add integration regression: Reset clears state and returns root navigation to onboarding; cancelled Reset does neither.
- [ ] Run affected Swift suites and settings/failure Maestro journeys. Compare settings screenshots in both appearances; commit.

## Task 6: Native app switch and upgrade proof

**Files:** WhimIPhoneApp.swift, ios/whim/AppDelegate.swift, SceneDelegate.swift, Info.plist, project/scheme/workspace, scripts/configure-xcode-project.rb; UpgradeCompatibility.integration.test.swift; scripts/test-iphone-e2e.sh; e2e/iphone/flows/clean-launch.yaml and other iPhone flows.

- [ ] Before removing the old app, create a sanitized pre-migration SQLite/audio/preferences fixture with queued and delivered Notes and completed onboarding. Add a compatibility test that opens it through production-compatible native stores and asserts public queries and audio playback eligibility. Preserve a deterministic fixture manifest documenting creation revision.
- [ ] Run a failing native startup journey without Metro, then switch the main app to SwiftUI and link WhimCore through SPM. Preserve all existing identity/storage constants and Watch embedding. Keep URL handling appropriate to existing product routes; remove Expo dev-client routes.
- [ ] Replace iPhone E2E startup with direct launch, preserve WhimFixtureAudio/WhimFixtureWebhookURL and peer fixtures, remove EXDevMenu/EXPO_DEV_CLIENT_URL and Metro work. Preserve isolated webhook startup, process cleanup, failure artifacts and simulator installation.
- [ ] Install the old build, create data, then install the new build over it without uninstall/clearState. Verify Notes, settings and audio; mark physical Keychain/paired-Watch checks separately. Ordinary isolated E2E remains clean-state.
- [ ] Run all iPhone journeys plus Watch/cross-device suites and upgrade integration tests. Commit.

## Task 7: Remove Expo and verify the repository

**Files:** package.json/package-lock.json, app.json, metro.config.js, jest.config.js, tsconfig.json, packages/expo-whim, packages/WhimCore/WhimCore.podspec, ios/Podfile and lock/properties, supporting Expo files/bridging header, scripts/wait-for-metro.mjs and test, scripts/test-all.sh/test-swift.sh, .github/workflows/test.yml; all retired src/iphone TypeScript files; v1 design and development docs.

- [ ] Map every retired test to its native companion or unchanged WhimCore coverage before removal. Delete runtime/UI dependencies and bridge-only sources; retain Node webhook tooling and its tests. Regenerate the lockfile. Remove Pod references, React build settings/phases, and Expo-specific resources only where not needed to preserve current appearance. Preserve current app icon pixels if renaming Expo-named icon resources.
- [ ] Update root runners: unit runs Node tooling tests plus Swift unit tests; integration runs core, iPhone and Watch integration; E2E runs both installed-app suites. Replace obsolete TypeScript typecheck with native compile validation or remove its invocation; do not leave a no-op check. CI retains script tests and full macOS verification, without pod install.
- [ ] Make project configuration repeatable: run it twice and verify the second run causes no project diff. Ensure colocation rules cover all new Swift tests and exclude test sources from shipping targets.
- [ ] Update v1 architecture/test-seam sections and native build instructions. Preserve historical plans as history; distinguish historical mentions from active dependencies in the reference audit.
- [ ] Run full verification:

```sh
npm ci
npm run test:all
xcodebuild build -workspace ios/Whim.xcworkspace -scheme Whim -configuration Release -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO
xcodebuild build -workspace ios/Whim.xcworkspace -scheme WhimWatch -configuration Release -destination 'generic/platform=watchOS' CODE_SIGNING_ALLOWED=NO
git diff --check
rg -n 'ExpoModulesCore|WhimCorePod|ReactNative|expo-router|EXPO_DEV_CLIENT_URL|wait-for-metro' src ios scripts package.json .github
```

- [ ] Inspect built Release app/framework contents and debug fixture exclusion; perform clean builds using a fresh derived-data directory so cached Pods cannot conceal missing wiring. Record exact results, screenshot parity checks and outstanding physical acceptance. Resolve failures before claiming completion; commit and perform final branch review.

## Execution handoff

Recommended: native execution in this session, followed by a fresh final reviewer. The tasks share lifecycle, model, project and test-runner changes, so keeping implementation context together reduces coordination overhead. Subagent-driven implementation is also available if the user prefers an independent review after each task. No product code changes precede plan review and execution selection.
