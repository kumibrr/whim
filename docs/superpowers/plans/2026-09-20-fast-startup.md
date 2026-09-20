# Fast Startup Implementation Plan

> **For agentic workers:** Use superpowers:executing-plans for inline implementation. Track each test-driven slice below.

**Goal:** Show onboarding/capture early and allow recording independently of deferred maintenance, with actionable glass errors.
**Architecture:** Separate capture preparation from full launch; take a fixed recovery inventory before capture, process it in the background, and coordinate mutations against recovery. Publish a lightweight startup projection before auxiliary snapshots.
**Tech Stack:** Swift 6, SwiftUI, SQLite/GRDB, AVFoundation, XCTest/Maestro.
**Spec:** `docs/superpowers/specs/2026-09-20-fast-startup-design.md`

## Global Constraints

- Keep iPhone tap-to-record, Watch first-activation auto-record, and existing permission behavior.
- Transfer submission, HTTP completion, and title completion never gate capture readiness.
- Recovered playable audio remains a review-required Note.
- Run affected suites throughout implementation and `npm run test:all` before declaring completion.

## Review Focus

- A second service sees a live writer: recovery must not touch its audio.
- Delete/reset overlaps suspended recovery: deleted data cannot reappear.
- Delayed auxiliary projection overwrites capture: newer events must win.
- Initialization fails then succeeds: retry must replace failed single-flight state.
- Watch permission state is unknown: do not flash permission-denied UI or auto-record twice.

### Task 1: Fixed recovery inventory and live-writer protection

Files: `Recovery/RecoveryScanner.swift`, its integration test, `Notes/AudioFileStore.swift`, `Recording/RecordingService.swift`, and existing package membership when adding files.

Interface: `RecoveryScanner.inventory() async throws -> RecoveryInventory`; `scan(_ inventory: RecoveryInventory) async throws`; `AudioFileManaging.claimOwnership(noteID:) throws -> AudioFileOwnership?`. Default test adapters can return an unowned token; production uses an advisory lock held until recording/recovery releases it.

- [x] Add and run failing public storage/recording regressions: inventory excludes later sessions; independent service cannot recover a live writer; deletion does not resurrect an inventoried Note.
- [x] Implement fixed candidate enumeration and lifetime ownership; check cancellation between candidates.
- [x] Run `swift test --package-path packages/WhimCore --filter RecoveryTests` and recording integration tests. Expected: all pass.

Core regression shape:
```swift
let inventory = try await scanner.inventory()
let session = try await recording.start(source: .iphone)
try await scanner.scan(inventory)
let active = await recording.snapshot()
XCTAssertEqual(active?.sessionID, session.sessionID)
```

### Task 2: Capture readiness independent of maintenance

Files: `AppComposition/WhimClient.swift`, `WhimService.swift`, service integration tests, `DeviceSync/ConnectivityMergeService.swift`, `WebhookConfiguration/ConfigurationTestService.swift` and companion tests.

Interface: `WhimClient.startup() async throws -> StartupProjection` containing onboarding, microphone and recording; `prepareCapture()` establishes safe inventory; `launch()` joins full maintenance for history-dependent operations. Production composition returns after construction rather than full launch. Startup failure is retryable. Maintenance never holds the capture command gate. Reset/delete join recovery before their destructive mutation; capture operations join only preparation. Settings/read waits occur outside capture serialization.

- [x] Add failing service tests that suspend recovery or auxiliary permission reads, then start/stop capture before releasing the suspension.
- [x] Split persisted reset recovery from normal peer replay. Perform pending reset before inventory; defer peer replay, audio scan and existing Note workflows. Retry failed tasks without reinventorying live sessions.
- [x] Add a lazy fixture URL provider to configuration testing; resolve it only on send.
- [x] Run service, recovery, configuration-test and cross-device integration suites. Expected: capture independent; reset/deletion/Receipt tests remain green.

Concurrency regression shape:
```swift
let background = Task { try await client.launch() }
await boundary.waitUntilBlocked()
let captured = expectation(description: "capture independent of maintenance")
let capture = Task {
    _ = try await client.startRecording(source: .iphone)
    _ = try await client.stopRecording()
    captured.fulfill()
}
await fulfillment(of: [captured], timeout: 2)
await boundary.release()
try await capture.value
try await background.value
```

### Task 3: Progressive iPhone and Watch presentation

Files: iPhone/Watch app entry points, root views, presentation models and adjacent integration tests; iPhone OnboardingView.

Interface: models expose startup projection independently from full settings/history, plus separate preparation/auxiliary error states. Initial onboarding flag is a hint read from the same store. Recording commands refresh lightweight capture state rather than waiting for history.

- [x] Add failing model tests holding an auxiliary system boundary suspended while startup/capture publishes.
- [x] Mount shells immediately; join one composition task; publish startup before auxiliary work. Preserve event sequence/generation reconciliation. Watch first activation starts once after known permission, then loads recent Notes/settings.
- [x] Run `swift test --filter WhimIPhoneIntegrationTests` and Watch model tests with the existing script/simulator destination. Expected: old lifecycle cases and new blocked-boundary cases pass.

### Task 4: Actionable glass errors

Files: existing iPhone theme/error/model/root files and Watch model/capture view; add focused error model tests where needed.

Interface: typed recovery action (retry, settings, instructions), readable message, blocking priority and in-flight state. Native views present one top-half rounded glass container and dispatch the typed action. Prioritize storage and permission issues over auxiliary errors.

- [x] Add failing message/action tests for preparation, permission, disk-full and auxiliary errors.
- [x] Implement actual resolving actions and device-specific guidance, accessible fallback materials, duplicate-tap protection and removal on success. Keep Stop/Discard reachable.
- [x] Add installed-app failure/retry and permission guidance coverage; regenerate Xcode membership with `ruby scripts/configure-xcode-project.rb`.
- [x] Run focused tests and compile both native targets. Expected: actionable accessible containers, no plain raw-error startup screen.

### Task 5: Verification and documentation

Files: `docs/startup-flow.md`, existing E2E/physical procedures, this plan's progress ledger.

- [x] Update sequence documentation and document measured vs structurally proven improvements. Instrument local startup milestones without content/telemetry if useful for before/after runs.
- [x] Run `npm run test:all`; report actual failures or environment blockers without claiming unrun tests passed.
- [x] Get one independent final review, resolve important findings with regression coverage, and check the final diff.

## Execution ledger

User explicitly requested implementation after spec review; proceed inline without another approval checkpoint. Existing worktree is already isolated. Earlier README/startup-trace changes belong to this task and must be preserved. Disk availability is limited; remove only disposable build artifacts created by this run if needed.


### Outcomes and rulings

- Capture preparation now resolves pending reset and freezes metadata candidates; audio validation, peer work, history, and optional settings are deferred. Peer replay precedes validation because both mutate the same Notes.
- Recording and recovery share file-descriptor ownership across separately composed services. Fixed-inventory tests exclude later recordings and discarded sessions.
- Destructive operations cancel and join maintenance before erasing. A recovery failure cannot disable Reset Whim. Maintenance generations prevent stale callers from restarting obsolete work.
- iPhone and Watch publish lightweight startup before optional snapshots. Tests suspend permissions/recovery/HTTP and still start and stop capture. iPhone onboarding completion routes before optional settings finish.
- Both interfaces show typed, actionable glass errors. Installed journeys cover denied permission and Watch preparation retry. A separate playback-failure regression proves Refresh cannot start recording.
- Independent scoped review found readiness, reset, and unrelated-action retry issues; all were addressed with deterministic regressions and re-reviewed. No remaining important issue was reported.
- First `npm run test:all` completed successfully, including nine iPhone E2E journeys and Watch E2E. Final complete rerun after the last review fixes also passed (exit 0): tooling/unit, core/iPhone/native integration, all nine iPhone E2E journeys, and Watch E2E.
- Watch denied-permission layout was visually inspected in the simulator: the glass card is below the clock with its action in the upper half.
- No numerical device speedup is claimed: tests establish removal of blocking dependencies. Cold/warm launch timing, physical microphone onset, wrist-down behavior, and large-text/reduced-transparency acceptance remain documented physical checks.


### Follow-up: preserve local access after maintenance failure

- Reproduced the user-visible regression with saved metadata and audio intact: `listNotes` and `playNote` propagated an unrelated recovery I/O error.
- Added the explicit `WhimClient.maintain()` seam. Essential preparation still guards local reads/capture; maintenance no longer gates list/detail/waveform/playback.
- Presentation retains local history while reporting maintenance separately; resumes recovery after deletion cancellation.
- Playback errors identify the audio/player problem, retry the same Note, appear inside history, and clear when leaving their presentation surface.
- Added core/model regressions plus an installed playback-error journey. No physical-device data was mutated; actual storage verification is pending device access.


Follow-up verification: 102 core integration tests and 38 iPhone integration tests passed. The installed playback-failure/retry journey passed with its error/action inside history. `npm run test:all` passed unit/integration and nine of ten iPhone journeys; the sole failure was the simulator Settings destination label (`Whim` versus Settings home). The assertion now accepts either system destination and its targeted rerun passed. All 14 Watch UI tests passed separately; the final playback rerun against the rebuilt app also passed, including visible in-sheet error, same-Note retry, and successful playback. Reviewer findings about cancellation and stale playback retries were fixed and regression-tested.

Physical inspection clarification: the connected phone is reachable, but Apple’s file service refuses top-level `Whim/whim.sqlite`, exposing only Library/Documents/tmp. No conclusion about missing physical files can be drawn from that filtered listing. No app data on the phone was changed.


### Follow-up: compact whole-card recovery action

User clarified that the entire glass error container should be clickable and smaller. iPhone/Watch now use one content-sized button with wrapped message and chevron; the separate action row and fixed-height scroll region are removed. VoiceOver receives the full message/action hint, busy state disables the whole control, and auxiliary dismissal is available through a horizontal swipe or accessibility action.

Installed tests now target the whole card, reject the old inner action button, and bound the Watch permission card to less than 30% of the screen height. The Watch test taps near the card's upper-left edge. The Watch simulator screenshot confirmed the compact appearance below the clock. Initial pre-change Watch test attempts stalled in the runner and were stopped; no successful red-cycle result is claimed. The iPhone setup flow now handles an undetermined microphone permission instead of assuming simulator pregrant always completed.


Compact-card verification: unit/integration checks and all ten iPhone journeys passed. The full run exposed a Watch startup accessibility identifier being inherited from its parent; explicit accessibility containers fixed it. The subsequent complete Watch UI suite passed (14 tests, no skips), including preparation retry, the under-30%-height check, and tapping the permission card near its edge. Final diff/colocation checks passed. No physical-device data was changed.
