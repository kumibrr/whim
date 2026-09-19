# SwiftUI migration design

Date: 2026-09-19
Status: Approved by user on 2026-09-19

## Intent

Replace the entire React Native/Expo iPhone app with SwiftUI. Preserve the current screens and flows, as explicitly requested: layout, navigation, copy, actions, confirmations, status treatment, and accessibility. This migration does not expand the implemented feature set.

Keep iOS 18 and watchOS 11 minimums, the Swift Watch app, WhimCore behavior, webhook contract, app identity, existing data, and credentials.

## Approach

Replace the presentation layer directly, working in tested vertical slices and retaining the old sources as a parity reference until their replacement passes. The final app has no React Native, Expo, JavaScript bundle, or Metro runtime dependency.

A hybrid app would retain two UI runtimes and bridge complexity. Rewriting WhimCore would increase risk without serving the migration. Reuse the existing Swift WhimClient commands and projections instead.

## Native composition

A SwiftUI app entry point replaces the Expo AppDelegate and React Native SceneDelegate. A main-actor observable presentation model calls WhimClient and consumes native events; WhimCore remains authoritative for Notes, Recording Sessions, Delivery, settings, and playback.

Move required service construction and lifecycle behavior out of the Expo module. Preserve launch recovery, foreground refresh, background transitions, Watch Connectivity startup, and supported incoming routes. Audit existing target and extension wiring before removing bridge files.

Subscribe before loading snapshots. Preserve event sequencing and gap recovery, ignore stale events, and prevent old snapshots from overwriting newer events or refreshes. Cancel observation with its owner. Surface sanitized errors and prevent duplicate asynchronous actions. Native events drive recording progress and playback state.

Use SwiftUI navigation for the existing home, onboarding, settings, and Note-detail destinations, preserving back navigation, onboarding gating, and active recorder restoration.

## Screen parity

- Timeline: existing layout, Settings action, chronological rows, filters, statuses, individual/bulk Retry, loading/error/empty states, and Record.
- Recorder: elapsed time, waveform/meter, duration progress and warning, Stop, confirmed Discard, visible/haptic feedback, and contextual permissions after saving.
- Note detail: playback, metadata, Delivery details, Retry, recovered Note review/Send, and deletion confirmation rules.
- Settings: webhook fields and masked secrets, custom headers, save/test feedback and retry offers, retention, transcription/language, permissions, Watch status, and confirmed Reset.
- Onboarding: explanation, setup/test or Skip, microphone permission, and completion.

Retain accessibility identifiers where possible. Preserve Light/Dark Mode, Dynamic Type, VoiceOver, non-color status cues, Reduce Motion, and focus order. Capture representative baseline simulator screenshots before replacing screens and compare the native equivalents.

## Upgrade compatibility

Keep bundle identifiers, app groups, entitlements, database/audio paths, preference keys, and Keychain attributes unchanged. Do not reset stores. Verify pre-migration Notes, pending Delivery, settings, onboarding state, and retained audio remain usable. Device-only Keychain and paired-Watch upgrade behavior require physical acceptance.

## Build and cleanup

Keep the committed Xcode project, native schemes, resources, signing configuration, and Swift package integration. Remove Expo/React Native imports, bridge targets, Expo-only CocoaPods dependencies and build phases, JS bundling, Metro, Expo configuration, TypeScript UI sources, and obsolete tests after native replacements pass.

Retain Node tooling for repository scripts and the webhook fixture where useful. Keep root test:unit, test:integration, test:e2e:iphone, test:e2e:watch, test:e2e, and test:all commands runnable. Update project configuration scripts, CI, colocation checks, and development documentation so they build the native app without restoring Expo dependencies.

## Tests and acceptance

This design supersedes only the Expo-specific architecture and testing clauses in the approved v1 spec. Replace the Expo adapter seam with a native iPhone presentation interface exposing commands and observable projections over WhimClient. Other v1 behavior and seams remain applicable.

Port presentation rules to Swift unit tests. Integration tests compose presentation models with real owned services and isolated persistence, mocking system boundaries only. Preserve lifecycle and event-ordering regressions before deleting bridge tests. Retain accessibility-driven Maestro iPhone journeys and XCTest Watch journeys, removing Metro startup while preserving debug-only fixture audio and isolated webhook execution.

Each slice starts with a failing companion test at its public seam, followed by minimum implementation and the affected suite. Preserve onboarding, recording/review, offline/retry, failure/retry, recovered review, settings/reset, and Watch synchronization journeys. Add deterministic upgrade coverage using a pre-migration store fixture.

Completion requires test:all passing, clean builds of the existing native targets, a release build checked for runtime dependencies and debug switches, and a source/build reference audit. Record physical acceptance still outstanding; simulator tests do not establish microphone, wrist-down, background, App Intent, or paired-device hardware behavior.

## Sequence

1. Capture UI and behavior baseline; audit lifecycle, storage identity, targets, and tests.
2. Introduce native composition and presentation state with companion tests.
3. Port onboarding, timeline/recording, detail/playback, and settings/configuration as tested slices.
4. Switch the app entry point and verify installed-app parity and upgrade compatibility.
5. Remove Expo dependencies and obsolete tooling, update CI/docs, and run full verification.

A detailed implementation plan follows design approval.
