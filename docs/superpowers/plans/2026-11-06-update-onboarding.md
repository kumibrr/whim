# Update onboarding implementation plan

> **For agentic workers:** Use superpowers:executing-plans to implement these vertical test-driven slices in this session.

**Goal:** Present customizable update announcements to existing users while excluding fresh installs.

**Architecture:** A native iPhone presentation model owns announcement eligibility, local acknowledgement, and settings drafts. IPhoneModel initializes eligibility from its first durable startup projection. The root presents an onboarding-styled sheet only when capture and navigation permit it.

**Tech Stack:** Swift 6, SwiftUI, UserDefaults, XCTest, Maestro; no new dependencies.

**Spec:** `docs/superpowers/specs/2026-11-06-update-onboarding-design.md`

## Global constraints

- Native SwiftUI; iOS 18 minimum; retain the existing black appearance.
- Exclude fresh installs from their installed release's announcement, including after onboarding and relaunch.
- Persist explicit completion or skip; no server, telemetry, or automatic default changes.
- Recording startup and Stop remain accessible.
- Assertions use the existing native presentation and installed-app seams.

## Review focus

- Bootstrap older installations without an announcement marker.
- A new install interrupted during onboarding must remain excluded after restart.
- Reset during an in-flight settings save must not revive or acknowledge the wrong announcement.
- External recording must dismiss the sheet without acknowledging it.
- Concurrent history/navigation and inactive scenes must defer presentation.

### Task 1: Persistent eligibility and settings actions

**Files:** Create `src/iphone/onboarding/AppUpdateModel.swift` and its colocated integration test; modify `Package.swift` and `src/iphone/app-composition/IPhoneModel.swift`.

**Interfaces:** `AppUpdate` describes an ID, heading, detail, and native content sections. `AppUpdateModel` exposes `pendingUpdate`, `editor`, `prepare(onboardingCompleted:)`, `load()`, `complete()`, and `skip()`. IPhoneModel exposes `appUpdate` and `offersAppUpdate`.

- [x] Write and run failing tests for a fresh installation across onboarding and relaunch, old installs without markers, persisted skip, a later announcement, reset, draft save/skip, failed saves, and capture deferral.
- [x] Implement the minimum presentation behavior, saving only through WhimClient and persisting acknowledgement only after success.
- [x] Run `swift test --filter AppUpdateModelIntegrationTests` and the affected iPhone integration suite; expect zero failures.

### Task 2: Onboarding-styled update sheet

**Files:** Create `src/iphone/onboarding/AppUpdateView.swift`; modify `OnboardingView.swift`, `IPhoneRootView.swift`, `PreferencesView.swift`, and native layout integration coverage.

**Interfaces:** AppUpdateView consumes Task 1's model. OnboardingFrame gains an optional update heading that replaces onboarding progress. Native sections include information, quick-capture setup, on-device-title toggle, and retention picker.

- [x] Add installed-app upgrade and fresh-install journeys before UI implementation. The first compiled check was blocked by disk space, then caught missing target registration; the final installed journey is verified below.
- [x] Replace the legacy upgrade-only root branch with the update sheet; retain normal onboarding and its setup acknowledgement.
- [x] Keep one root sheet presentation for history and updates, disable swipe dismissal for settings drafts, and dismiss without acknowledgement when capture starts.
- [x] Reuse existing onboarding controls, and render narrow viewports at normal and accessibility text sizes.
- [ ] Run the affected compiled-app journeys and native layout suite; expect zero failures.

### Task 3: Final verification and review

**Files:** Update the v1 design's upgrade behavior, E2E runner, and changeset.

- [x] Run `npm run test:all`; inspect failures and logs.
- [x] Review the completed diff with a fresh reviewer, fix substantive findings with regression coverage, and rerun affected suites.
- [x] Attempt the default development-signed iPhone install build using Sqim.
- [x] Report verification results and any remaining environment limitations.

## Verification record

- Fresh review found a retained-draft overwrite. The added regression reproduced retention and language reverting, then passed after Continue merged only edited announcement controls into current preferences.
- All 62 iPhone presentation integration tests pass, including eight update cases.
- The full-run tooling suite passed all 88 cases. Swift unit and integration suites passed before a simulator test-host launch failure stopped the aggregate.
- Retried `npm run test:integration` sequentially: all stages passed, including native update layouts, iOS audio adapters, and Watch tests.
- Build caches use external storage because the internal disk filled during initial compilation. No product behavior was changed to accommodate the environment.

- E2E limitation: Maestro could not start its iOS driver before any flow, including a retry with MAESTRO_DRIVER_STARTUP_TIMEOUT=180000. Watch E2E did not run because iPhone E2E stopped first.
- Direct inspection confirmed the sheet renders. A later interaction check was blocked by an Apple-runner build failure; its suggested shared-cache cleanup was left untouched because another active session uses that cache.
