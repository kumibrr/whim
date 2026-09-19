# Recording-first iPhone Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deliver the approved black-and-white recording-first iPhone interface with a reactive line, glass controls, interactive history sheet, and playable waveform cards.

**Architecture:** WhimCore continues to own capture, Notes, delivery, and playback. Extend its typed client with an audio waveform query; extend the iPhone presentation model with navigation and inline playback state. Small SwiftUI views own rendering and interactive sheet geometry.

**Tech Stack:** Swift 6, SwiftUI, AVFoundation, XCTest, Maestro, existing Swift packages and Xcode project. No new dependencies.

**Spec:** `docs/superpowers/specs/2026-09-19-iphone-recording-first-design.md`

## Global Constraints

- The minimum iPhone deployment version remains iOS 18.
- Watch UI and behavior are unchanged.
- Use a black background, white primary text and accents, and subdued gray secondary text.
- The idle hint reads exactly: "scroll to see previous notes."
- During recording, only Stop and Discard are available.
- The live waveform never progressively fills the screen.
- After successful finalization, return to idle with the plain line. Do not automatically open history.
- Discard retains the existing confirmation and Keep recording escape action.
- Only one Note plays at a time; preserve existing play/stop semantics.
- Preserve v1 onboarding, permissions, delivery, recovery, retention, settings, and accessibility.
- Implement each behavior as a vertical test-driven slice. Run `test:all` before declaring implementation complete.

## Review Focus

1. External recording starts while settings/detail/history is open: dismiss navigation, cancel inline playback, and expose only recording actions (Task 1).
2. Deletion/retention races with waveform decoding: a late decode must not restore available audio or a deleted card (Task 3).
3. A delayed playback snapshot returns after switching Notes or dismissing: never restore the old player (Task 4).
4. A history drag is canceled, or the user scrolls within an open list: no opening haptic on cancellation and no accidental sheet dismissal (Task 2).
5. Accessibility text sizes, Reduce Transparency, and absent/corrupt audio: controls and status remain readable and actionable without decorative waveform data (Tasks 3 and 5).

## File responsibilities

- `src/iphone/app-composition/IPhoneModel.swift`: observable recording restrictions, history visibility, inline playback commands/progress, and bounded waveform presentation state.
- `src/iphone/app-composition/IPhoneRootView.swift`: navigation orchestration, recording focus, preserved onboarding/permission/error presentation.
- `src/iphone/recording/CaptureHomeView.swift`: idle layout and capture controls.
- `src/iphone/recording/RecorderView.swift`: active layout, elapsed/limit information, Stop and confirmed Discard.
- `src/iphone/recording/LiveWaveformView.swift`: full-width microphone-driven line; no audio capture ownership.
- `src/iphone/appearance/GlassSurface.swift`: supported native glass, material fallback, and accessibility contrast.
- `src/iphone/appearance/IPhoneTheme.swift`: monochrome iPhone palette and existing typography helpers.
- `src/iphone/timeline/HistorySheet.swift`: direct drag interaction, open/close transitions, and one opening haptic.
- `src/iphone/timeline/TimelineView.swift`: existing list/filter behavior inside history, without its floating Record button.
- `src/iphone/timeline/NoteRowView.swift`: metadata, independent detail/player actions, status and retry.
- `src/iphone/timeline/NoteWaveformView.swift`: saved audio samples and playback progress rendering.
- `packages/WhimCore/Sources/WhimCore/Playback/AudioWaveform.swift`: public bounded sample projection and audio-decoder boundary.
- `packages/WhimCore/Sources/WhimCore/Playback/AVAudioWaveformAdapter.swift`: chunked decoding and bounded in-memory cache.
- `packages/WhimCore/Sources/WhimCore/AppComposition/WhimClient.swift` and `WhimService.swift`: waveform query and availability/race protection.

Keep model code in the root package's `modelSources`; register new companion tests in its explicit unit/integration lists. Register core sources/tests in `packages/WhimCore/Package.swift`. New SwiftUI files require PBX file references, build files, group entries, and iPhone Sources membership in `ios/whim.xcodeproj/project.pbxproj`; do not compile package model files a second time in the app target.

## Execution preparation

- [ ] Read `AGENTS.md`, `CONTEXT.md`, the v1 spec, and the approved redesign spec. Use using-git-worktrees at execution time; preserve any unrelated user changes.
- [ ] Establish the toolchain and baseline with the existing scripts:

```bash
source scripts/apple-toolchain.sh
npm run test:unit
```

Record pre-existing failures. For simulator commands below, first run the repository's simulator setup in the same shell:

```bash
eval "$(./scripts/boot-apple-simulators.sh)"
```

## Task 1: Recording-first home and exclusive recording actions

**Files:** Modify `IPhoneModel.swift`, `IPhoneModel.integration.test.swift`, `IPhoneRootView.swift`, `RecorderView.swift`, `IPhoneTheme.swift`, and `ios/whim.xcodeproj/project.pbxproj`. Create `CaptureHomeView.swift`, `LiveWaveformView.swift`, and `GlassSurface.swift` in the directories above. Modify `e2e/iphone/record-and-review.e2e.test.yaml` and existing journeys whose first screen changes.

**Interfaces:** Add to `IPhoneModel`:

```swift
public private(set) var isHistoryPresented = false
public var canBrowse: Bool { recording == nil && !isRecordingPending }
public func openHistory() {
    guard canBrowse else { return }
    isHistoryPresented = true
}
public func closeHistory() async
```

`closeHistory()` clears presentation; Task 4 adds playback cleanup. Normalize history state both after snapshot refresh and after recording/reset events. A recording start also clears the root navigation path and any settings/detail presentation. A cold link must not bypass the recording restriction.

- [ ] Add this failing integration case to the existing `IPhoneModelIntegrationTests`:

```swift
func testRecordingClosesHistoryAndStopStaysIdle() async throws {
    let harness = try WhimFacadeHarness()
    defer { harness.remove() }
    let model = IPhoneModel(client: harness.makeService(permissions: GrantedPermissions()))
    await model.start()
    defer { model.stop() }
    model.openHistory()
    XCTAssertTrue(model.isHistoryPresented)
    await model.startRecording()
    XCTAssertFalse(model.isHistoryPresented)
    XCTAssertFalse(model.canBrowse)
    model.openHistory()
    XCTAssertFalse(model.isHistoryPresented)
    await model.stopRecording()
    XCTAssertTrue(model.canBrowse)
    XCTAssertFalse(model.isHistoryPresented)
}
```

- [ ] Run `source scripts/apple-toolchain.sh` then `swift test --filter IPhoneModelIntegrationTests/testRecordingClosesHistoryAndStopStaysIdle`; observe the missing presentation interface failure.
- [ ] Implement the model interface and state normalization. Add external-start coverage by invoking the real service's `startRecording(source: .iphone)`, then awaiting observable recording state using the existing bounded event-wait convention. Assert history closes without calling the model's start command. Retain permission and failed-command tests.
- [ ] Change the installed-app journey before the layout implementation:

```yaml
- tapOn:
    id: record-button
- assertVisible:
    id: recorder-panel
- assertNotVisible:
    id: settings-button
- assertNotVisible:
    id: history-hint
- tapOn:
    id: stop-recording
- assertVisible:
    id: record-button
- assertNotVisible:
    id: history-sheet
```

Run `WHIM_IPHONE_E2E_FLOW=record-and-review.e2e.test.yaml npm run test:e2e:iphone` with simulator variables loaded; establish the changed journey's failure before implementing it.
- [ ] Implement home using a black safe-area-filling background, centered horizontal line, bottom 76-point circular Record control, top-right 48-point icon control, and the exact hint. Keep `whim-home`, `record-button`, `recorder-panel`, and `stop-recording` identifiers stable. Add `settings-button`, `history-hint`, and `live-waveform`.
- [ ] Implement a continuous full-width path whose vertical displacement uses the current microphone level. For normalized x in 0...1, use this initial visual envelope, tuning only the visual constants during inspection:

```swift
let level = power.isFinite ? max(0, min(1, (power + 60) / 60)) : 0
let envelope = sin(.pi * x)
let displacement = level * availableHeight * 0.35
    * envelope * sin(8 * .pi * x)
```

Use zero level while idle and when stopped. Smooth level changes over approximately the existing 100 ms metering interval, disable interpolation for Reduce Motion, and do not animate a phase or grow a fill width. Expose microphone level and recording duration through accessibility, not each path point.
- [ ] Keep elapsed time, duration progress/warning, and confirmed Discard. Do not expose contextual permission prompts, microphone-settings links, or other root controls while recording; defer optional prompts until idle. Reject duplicate pending capture commands using existing guards.
- [ ] Implement shared glass styling after checking the installed SwiftUI SDK's native glass declarations and availability; consult official Apple documentation if needed. Use a runtime availability branch for native glass and an iOS 18 material/stroke fallback. Reduce Transparency selects an opaque dark surface. Force the iPhone presentation to dark with white tint without changing Watch styling.
- [ ] Run the affected presentation suite and the updated recording E2E flow. Commit the self-contained home change after the affected existing journeys are adapted to use the temporary tap-open history presentation; Task 2 adds direct manipulation.

## Task 2: Finger-following history sheet

**Files:** Create `src/iphone/timeline/HistorySheet.swift`; modify `IPhoneRootView.swift`, `TimelineView.swift`, Xcode Sources membership, and `e2e/iphone/record-and-review.e2e.test.yaml`. Create `e2e/iphone/history-sheet.e2e.test.yaml` and register it in `scripts/test-iphone-e2e.sh`.

**Interfaces:** `HistorySheet<Content: View>` takes a Boolean presentation binding, `isEnabled: Bool`, an `onOpened: () -> Void` callback, and a content builder. Root bridges the binding to `openHistory()` / `closeHistory()`. Haptic delivery belongs to `onOpened`, not drag updates. `TimelineView(model:open:)` remains the list's public view interface.

- [ ] Add the new clean-launch journey with a swipe from the lower idle area, history visibility, downward dismissal, and hint tap reopening:

```yaml
appId: app.whim.ios
---
- runFlow: flows/clean-launch.yaml
- swipe:
    start: 50%, 85%
    end: 50%, 30%
    duration: 600
- assertVisible:
    id: history-sheet
- swipe:
    start: 50%, 15%
    end: 50%, 90%
    duration: 600
- assertVisible:
    id: history-hint
- tapOn:
    id: history-hint
- assertVisible:
    id: history-sheet
```

- [ ] Run `WHIM_IPHONE_E2E_FLOW=history-sheet.e2e.test.yaml npm run test:e2e:iphone` and observe the missing drag interaction failure.
- [ ] Implement a bottom overlay whose visible height is driven by vertical translation during the opening gesture. Use a 20% screen-height opening threshold or a predicted endpoint beyond it. Clamp offsets to the closed/open range. On commit, update presentation once and deliver one opening callback. A canceled drag returns to idle with no callback.
- [ ] Give the open sheet a drag handle for downward dismissal, a close accessibility action, and a dimmed background. Restrict sheet dismissal drag ownership to the handle; the nested timeline ScrollView retains list gestures. Keep background capture/settings inaccessible while the sheet is open.
- [ ] Add installed-app coverage for a short canceled opening drag, then a long drag, and for scrolling a list containing enough fixture Notes to overflow without dismissing the sheet. Assert visible state, not pixel-perfect offsets. Add physical haptic checks in Task 6.
- [ ] Re-run the history and recording flows, then commit the gesture slice. Preserve all filters, retry, empty/error states, and navigation back to the same open history after detail.

## Task 3: Real audio waveform query

**Files:** Create `Playback/AudioWaveform.swift`, `Playback/AVAudioWaveformAdapter.swift`, and `Playback/AVAudioWaveformAdapter.integration.test.swift` under WhimCore. Modify `WhimClient.swift`, `WhimService.swift`, `packages/WhimCore/Package.swift`, and `src/iphone/app-composition/IPhoneModel.integration.test.swift` for facade-level regression coverage using its existing harness.

**Interfaces:**

```swift
public enum AudioWaveform: Equatable, Sendable {
    case samples([Float])
    case unavailable
}
public protocol AudioWaveformAdapter: Sendable {
    func waveform(at url: URL) async throws -> [Float]
}
// WhimClient requirement and default returning .unavailable:
func waveform(noteID: NoteID) async throws -> AudioWaveform
// WhimService initializer adds a defaulted parameter:
// waveform: any AudioWaveformAdapter = AVAudioWaveformAdapter()
```

The concrete adapter is an actor, returns exactly 64 finite amplitudes in 0...1 for valid nonempty audio, and keeps at most 64 cached results. File identity includes URL, modification date, and size. Cancellation does not populate the cache.

- [ ] Add a facade integration test before the implementation:

```swift
func testWaveformDoesNotSurviveAudioRemoval() async throws {
    let harness = try WhimFacadeHarness()
    defer { harness.remove() }
    let client = harness.makeService(permissions: GrantedPermissions())
    _ = try await client.startRecording(source: .iphone)
    let saved = try await client.stopRecording()
    let id = try XCTUnwrap(saved).id
    let first = try await client.waveform(noteID: id)
    guard case .samples(let samples) = first else { return XCTFail("Expected audio samples") }
    XCTAssertEqual(samples.count, 64)
    XCTAssertTrue(samples.allSatisfy { $0.isFinite && (0...1).contains($0) })
    try harness.files.delete(noteID: id)
    let removed = try await client.waveform(noteID: id)
    XCTAssertEqual(removed, .unavailable)
}
```

- [ ] Run `swift test --filter IPhoneModelIntegrationTests/testWaveformDoesNotSurviveAudioRemoval` after sourcing the toolchain and observe the absent-query failure.
- [ ] Implement the query with Note lookup and local-audio validation before cache/decode and again after the await. Return `.unavailable` for absent, expired, unreadable, or deleted audio. Propagate cancellation. A waveform failure never changes delivery state or prevents an independent playback attempt.
- [ ] Decode with `AVAudioFile` using float PCM chunks of at most 4096 frames; accumulate peak absolute amplitude into 64 bins using absolute frame position. Clamp finite samples and treat nonfinite input as zero. Do not normalize silence to a visible signal. Check cancellation each chunk; do not allocate the entire recording. Keep decoding outside WhimService's command lock so capture can start during decoding.
- [ ] Add adapter integration fixtures generated with AVFoundation: all-zero audio produces 64 zeros; a first-half tone and second-half silence produces nonzero early bins and zero late bins; a missing/corrupt file throws. Assert public adapter output, not private cache contents.
- [ ] Add a gated system decoder boundary to the existing facade harness through its `makeService` parameter. Start a query, delete the Note through the real client while decoding waits, release it, and assert `.unavailable`. Repeat for removed local audio. Add a start-recording-during-decode test to ensure waveform work never serializes capture behind long decoding.
- [ ] Run `swift test --package-path packages/WhimCore --filter WhimCoreIntegrationTests` and `swift test --filter IPhoneModelIntegrationTests`; commit the waveform query slice.

## Task 4: Inline playback state and lifecycle

**Files:** Modify `IPhoneModel.swift`, `IPhoneModel.integration.test.swift`, and `IPhoneModel.test-support.swift`.

**Interfaces:** Add `playInline(_ id: NoteID) async`, `stopInlinePlayback() async`, and `refreshInlinePlayback() async` to `IPhoneModel`. Reuse its existing observable `playback: PlaybackProjection?`. Add `loadWaveform(_ id: NoteID) async` and observable `waveforms: [NoteID: AudioWaveform]`, bounded to 64 entries; requesting visible rows drives loading.

- [ ] Add this failing lifecycle test:

```swift
func testClosingHistoryStopsInlinePlayback() async throws {
    let harness = try WhimFacadeHarness()
    defer { harness.remove() }
    let client = harness.makeService(playback: FacadePlayback(), permissions: GrantedPermissions())
    let model = IPhoneModel(client: client)
    await model.start()
    defer { model.stop() }
    await model.startRecording()
    await model.stopRecording()
    let id = try XCTUnwrap(model.notes.first).id
    model.openHistory()
    await model.playInline(id)
    XCTAssertEqual(model.playback?.noteID, id.rawValue.uuidString.lowercased())
    await model.closeHistory()
    XCTAssertNil(model.playback)
    let hardwareState = await client.playbackSnapshot()
    XCTAssertNil(hardwareState)
}
```

- [ ] Run `swift test --filter IPhoneModelIntegrationTests/testClosingHistoryStopsInlinePlayback` to observe the missing commands.
- [ ] Implement playback commands using the existing client and its single player. Serialize play/stop transitions and invalidate old generations before awaited commands. Reject play while history is closed, recording is active, or the selected Note lacks audio. Capture errors in existing `IPhoneError` presentation.
- [ ] Poll playback snapshots every 100 ms only while an inline player is active. Use `refreshInlinePlayback()` for each polling iteration and direct deterministic integration assertions. Gate results by selected Note, generation, recording state, history visibility, and task cancellation.
- [ ] Stop and invalidate inline work when closing history, navigating to detail, starting recording, deleting its Note, resetting, or stopping model observation. Scene inactivity cancels polling; foreground refresh reconciles canonical playback before restarting observation. Do not let root refresh overwrite a newer inline command result.
- [ ] Extend the existing `FacadePlayback` boundary with controllable completion and gated snapshots. Test two saved Notes: second play replaces first, completion clears state, and releasing an old snapshot after switching/dismissal cannot restore the first player. Test real service capture clears playback and deleting active audio removes playback availability.
- [ ] Load saved waveforms with per-request generation checks; remove entries on Note deletion/reset and invalidate samples when audio availability changes. A completed request for a vanished Note does not recreate presentation state.
- [ ] Run `swift test --filter IPhoneModelIntegrationTests` and `swift test --filter NoteDetailModelIntegrationTests`; commit the inline playback slice.

## Task 5: Glass Note cards with waveform players

**Files:** Modify `NoteRowView.swift`, `TimelineView.swift`, `IPhoneRootView.swift`, and `ios/whim.xcodeproj/project.pbxproj`. Create `src/iphone/timeline/NoteWaveformView.swift`. Modify recording/review, failed/retry, offline/retry, recovered-review, settings/reset, cold-links, onboarding, and Watch-synchronization iPhone YAML journeys for explicit history navigation.

**Interfaces:** Extend `NoteRowView` with `waveform: AudioWaveform?`, `playback: PlaybackProjection?`, and `togglePlayback: () -> Void`, retaining `note`, `open`, and `retry`. `NoteWaveformView(samples: [Float], progress: Double)` renders noninteractive audio data; seeking is not introduced.

- [ ] Add installed-app assertions before card implementation, after opening history on a saved Note:

```yaml
- tapOn:
    id: history-hint
- tapOn:
    id: note-play-.*
- assertVisible:
    id: note-stop-.*
- tapOn:
    id: note-stop-.*
- assertVisible:
    id: note-play-.*
```

- [ ] Run the recording/review flow and observe the absent inline controls.
- [ ] Implement cards with left-aligned title/date and right player; a supporting row retains duration, source, delivery/review status, availability, and Retry. Keep the existing `note-row-<uuid>` on the detail-opening button; place player and Retry beside it, never inside its button. Player identifiers use `note-play-<uuid>` and `note-stop-<uuid>`.
- [ ] Draw the 64 amplitudes in the available width; overlay played progress in white with unplayed samples in muted gray. Clamp progress to 0...1 and guard zero duration. Silence is a line. Missing/loading waveform uses a neutral line; expired audio disables the player and exposes its existing availability label.
- [ ] Use accessibility text size to switch the metadata/player layout from horizontal to vertical. Keep full title in its accessibility label, playback state/progress on its control, and minimum 48-point hit targets. Decorative paths are hidden from VoiceOver; status and errors retain labels/symbols.
- [ ] Connect visible-row waveform loading and inline commands; before opening detail await `stopInlinePlayback()`. Add failed/recovered/expired card checks to the owning existing journeys without repeating those domain assertions in every suite.
- [ ] Adapt every existing iPhone journey that assumes Notes are visible on launch/Stop to open history explicitly. Do not hide unrelated failures with conditional assertions. Keep direct settings/note links working when idle and verify external recording overrides those routes.
- [ ] Run `npm run test:e2e:iphone` with simulator setup, then commit cards and completed journey migration.

## Task 6: Visual acceptance, regression review, and final verification

**Files:** Modify `e2e/physical/iphone-presentation.e2e.test.md`; repair only issues exposed by verification in their owning code/tests. Update the approved design's implementation status when the work is actually complete.

- [ ] Add executable physical acceptance cases with steps and expected results: idle line, spoken-word level changes, silence, one opening haptic, canceled-drag silence, no history/settings while recording, stop without auto-history, interrupted/limit finalization, playback-to-record transition, VoiceOver, Reduce Motion, Reduce Transparency, and large text. Clearly mark physical cases pending until run on hardware.
- [ ] Build and inspect simulator screenshots for idle, active speech fixture, history, detail, and settings; include long-title, failed/recovered, and expired-audio cards. Use available current and iOS 18 runtimes to inspect native glass/fallback, or record an unavailable runtime as an explicit coverage limitation. Check safe-area spacing on a compact iPhone and larger text settings.
- [ ] Fix every discovered behavior bug with a failing regression at the lowest sufficient public seam before the fix. Visual-only spacing corrections need screenshot reinspection, not artificial unit tests.
- [ ] Run final checks once the implementation is stable:

```bash
git diff --check
npm run test:all
```

`test:all` provisions missing simulator identifiers and runs colocation, tooling, Swift unit/integration, iPhone E2E, and Watch E2E checks. A missing tool/runtime is a reported blocker, never a passing result.
- [ ] Follow the required code-review skill for the selected execution method, address actionable findings, and repeat only checks affected by fixes.
- [ ] Commit completed changes and report the implementation, automated results, visual evidence, and pending physical acceptance. Use finishing-a-development-branch for the integration handoff; do not push or merge without existing user authorization.

## Plan self-review

- Spec coverage: Task 1 owns home, live waveform, glass theme, and capture restrictions; Task 2 owns history gestures; Tasks 3–5 own real waveform cards and playback; Task 6 owns full verification and physical evidence.
- Interface consistency: all waveform results use `AudioWaveform`; all history state uses `isHistoryPresented`; inline playback reuses `PlaybackProjection` and the existing single-player adapter.
- Race coverage: explicit tests cover external capture, waveform deletion races, stale playback snapshots, and nonblocking capture while decoding.
- Accessibility/compatibility: fallback glass, motion/transparency settings, text-size reflow, accessible gesture alternatives, and hardware haptics have named acceptance cases.
- Execution recommendation: native execution in this session, because the six tasks share model and UI interfaces and benefit from one implementer's continuous context, followed by an independent final review.
