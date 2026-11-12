# Watch synchronization failure details implementation plan

> **For agentic workers:** Execute inline with superpowers:executing-plans. The user has already requested implementation by this agent; do not delegate implementation or create another worktree.

**Goal:** Show accurate causes, recovery guidance, and expandable technical facts for Watch availability and Note audio synchronization failures.

**Architecture:** Capture safe structured failures at system/protocol boundaries, project them through existing interfaces, and render them with native presentation models. Retain Note failure/history metadata in existing SQLite JSON fields. Optional fields and unknown reason values remain backward compatible.

**Tech stack:** Swift 6, WhimCore, SQLite/GRDB, native SwiftUI, XCTest, Maestro.

**Spec:** `docs/superpowers/specs/2026-11-12-watch-sync-failure-details-design.md` (approved).

## Global constraints

- iOS 18+, watchOS 11+; reuse existing native UI components, 48-point actions, Dynamic Type and VoiceOver semantics.
- Three transfers per Audio Synchronization cycle. Offline waiting, duplicate/stale replies and local save failures do not consume the budget.
- Preserve Receipt success, Delivery eligibility, handoff durability, tombstones and capture startup priority.
- Capture only safe domain/code/category/time. No raw messages, paths, URLs, secrets, titles, audio, telemetry or webhook diagnostics.
- Test public WhimClient/platform/presentation/installed-app seams with real owned modules and isolated persistence.
- Run root test:all under `/tmp/whim-pr-repair-test-all.lock` before completion; push normally to the existing fork head only.

## Review focus

- Legacy/future diagnostic values must not prevent loading Settings or a Note: codec tests in both tasks.
- Old callbacks/replies must not overwrite new failures or invent retries: event/CAS integration regressions in both tasks.
- A reachable change or historical transfer error must not change availability classification: Settings integration tests in task 1.
- Disk exhaustion while storing diagnostics must preserve the primary error and recoverable file: task 2 filesystem-boundary regression.
- Repair/manual retry must preserve historical causes and a Sent Receipt: task 2 restart and repair integration plus installed journey.

### Task 1: Watch status and technical details, end to end

**Files:** Add `DeviceSync/PeerConnectionDetails.swift` and its unit companion in WhimCore; update PeerTransport, WatchConnectivityAdapter, SettingsProjection, ConnectivityMergeService.status and WhimService.receivePeer. Extend existing service/protocol integration companions and add an iOS-only delegate test companion. Add `preferences/WatchConnectionDetails.swift` with a presentation companion and a reusable native `appearance/TechnicalDetailsView.swift`; update PreferencesView. Register SwiftPM/Xcode sources and the native test selector. Extend DebugPeerTransport and the existing Watch unavailability Maestro flow.

**Interfaces:** `SynchronizationSystemError(error:observedAt:)` exposes optional allowlisted domain/code and a fixed category. `PeerConnectionDetails` contains optional supported/activation/pairing/installation/reachability/queued-count facts, activation and transfer failures. Both existing peer/session protocols expose optional `connectionDetails`, default nil. WatchSettingsProjection adds optional connectionDetails. Add `statusChanged` to the existing platform and peer event enums. `WatchConnectionDetails(settings:)` exposes cause, recovery and labelled technical rows. No new public commands.

- [ ] Add failing codec/privacy and WhimClient.settings integration tests: literal boundary facts survive the real adapter/merge/service, unsupported is distinct from unknown, nil legacy fields decode, available/unreachable stays available, historical errors do not become current causes, and status changes emit settingsChanged without recovery gating.
- [ ] Run the relevant WhimCore filters; Expected: missing details/event behavior fails before implementation.
- [ ] Implement additive data/error classification, session capture/clear and event forwarding; keep statusChanged independent of the launch/recovery command path. Record safe current-session facts and clear activation failure on success.
- [ ] Add iOS delegate callback coverage through SystemWatchConnectivitySession and the real adapter; include its class in scripts/test-swift.sh's native integration selection.
- [ ] Add failing presentation tests for supported known/unknown reasons, safe technical rows and recovery guidance. Implement the presentation model, refresh action and native collapsed disclosure; add SwiftPM and Xcode membership.
- [ ] Extend deterministic system-session fixtures for unsupported and activation failure. Update Maestro to open Technical details and assert safe state/code fields. Run core and iPhone affected suites, then the targeted installed flow under the shared lock; Expected: green through the real Settings screen.
- [ ] Commit the tested Watch slice.

### Task 2: Persistent Note audio failure details, end to end

**Files:** Extend AudioSynchronization and companion tests, AudioTransferUnavailable, ConnectivityMergeService, SQLiteWhimStore retry bookkeeping, Note projections as needed, existing connectivity/store/service integration companions. Add `note-detail/AudioSynchronizationDetails.swift` with presentation tests; update NoteDetailView. Extend DebugPeerTransport audio scenarios and existing watch-audio-repair Maestro coverage. Keep root source registries/target membership complete.

**Interfaces:** `AudioSynchronizationFailure` holds tolerant string reason, observation time, request ID and optional SynchronizationSystemError. AudioSynchronization adds optional lastFailure; AudioSynchronizationRetry adds optional failure and completedAt. AudioTransferUnavailable adds optional source reason (missing Note/audio, expired, unreadable, not ready; legacy nil remains general unavailable). `AudioSynchronizationDetails(note:)` exposes cause/recovery and safe technical rows. Merge service accepts an injected Clock with a system default for deterministic observation times.

- [ ] Add failing public Note-projection integration tests for unreadable incoming audio and explicit Watch source-unavailable causes, including absent/future cause values, store/service reconstruction and safe metadata.
- [ ] Run those filters; Expected: failure details are absent before implementation.
- [ ] Capture causes at existing accepted rejection points and Watch store/file checks. Keep request/generation/deletion guards before metadata writes. Retain optional fields in existing JSON storage; decoding missing/future values must remain tolerant.
- [ ] Add failing cases for duplicate/stale responses, manual cycle replacement, successful repair with prior Receipt, retained history and local save failure without consuming transfers. Implement minimal bookkeeping and best-effort diagnostic recording that preserves original exceptions/files.
- [ ] Add failing presentation tests for failed/legacy/waiting/retrying/repaired Notes and source-specific recovery instructions. Add the native cause/recovery block and collapsed technical disclosure with transfer progress, IDs and enriched existing retry history. Keep webhook Delivery details separate.
- [ ] Extend installed fixtures and Maestro to expand details, inspect a cause and retry history, Retry sync, and observe repair of the same Note. Run affected core/iPhone suites and the targeted installed flow under the shared lock; Expected: green with unchanged retry/Receipt behavior.
- [ ] Commit the tested Note slice.

### Task 3: Final verification, review, screenshots and delivery

- [ ] Update physical acceptance procedures for actual OS failure reporting, VoiceOver and Dynamic Type; explicitly leave physical execution pending.
- [ ] Run `git diff --check`, root colocation checks and serialized `npm run test:all`; Expected: all unit/integration/native/iPhone/Watch E2E checks pass on the final source tree.
- [ ] Request one read-only whole-change review against the approved spec. Fix important findings personally with a failing regression and affected checks; do not delegate implementation or request repeated reviews.
- [ ] Use the Device tools and bound agent-device CLI for native screenshots of cause/recovery and expanded technical details. Show captures inline through html_preview/html_render.
- [ ] Verify the staged diff and actual fork head; commit remaining changes, push normally to MDsza/whim:feat/watch-unavailable-reason, link PR 57 as the next tool call, and report validation, limitations, SHA and GitHub state. Do not merge the PR.
