# Update-only onboarding

**Status:** Approved by the user on 2026-11-06

## Intent

Show existing Whim users what changed after an update, using a sheet built from the existing onboarding presentation. People installing Whim for the first time receive normal onboarding and never receive the announcement for the release they installed.

## Approach

The user chose to reuse the onboarding screen. Extend its presentation with an update mode rather than introduce a second visual system.

For eligibility, a release-specific announcement identifier is preferable to either reusing the single quick-capture acknowledgement or displaying something on every app-version change. The identifier lets a release deliberately introduce an announcement, including releases with interactive controls. Patch releases without an announcement do not interrupt users.

## Behavior

- Before normal onboarding can complete, establish whether this installation already completed onboarding.
- On a fresh installation, persist the current announcement as already covered. Completing onboarding or relaunching the same release must never show that announcement.
- An existing installation with completed onboarding and an unseen announcement receives the update sheet once.
- Existing installations without an announcement marker are eligible for the initial announcement. This bootstraps users of older Whim releases.
- Persist acknowledgement when the user explicitly finishes or skips the announcement. A later release with a different announcement identifier is eligible again.
- Defer presentation during a Recording Session, recording startup, history, another navigation destination, or inactive scene state. The sheet must not gate recording startup or hide Stop when capture begins through an external entry point.
- Reset Whim follows first-install behavior and does not immediately produce an update announcement after onboarding.

## Components and settings

Reuse the onboarding frame, typography, scrolling, buttons, accessibility behavior, and quick-capture guide. Update presentation has its own heading and no misleading onboarding step count.

Compose release content from native SwiftUI sections. Support informational content, the existing setup guide, and settings controls backed by the existing settings interface. New releases can choose the sections they need without changing eligibility logic.

Settings changes are drafts until the user continues. Save through the existing typed preferences interface; acknowledge only after a successful save. A skip action acknowledges the announcement without applying its draft. Failures remain visible and retryable.

Proposed initial content: reuse the existing quick-capture setup announcement. Provide reusable preference controls for on-device titles and audio retention without changing their defaults or describing existing behavior as newly introduced.

## Constraints and non-goals

- Native SwiftUI; iOS 18 minimum; preserve Whim's current black appearance and platform controls.
- No server, remote content, telemetry, or generalized component/plugin language.
- No change to first-install onboarding steps or Watch onboarding.
- Persist announcement state locally; app version and onboarding completion remain separate concepts.

## Verification

Use vertical test-driven slices through the native iPhone presentation interface. Cover fresh installs across onboarding completion and relaunch, existing installations with no marker, acknowledgement across relaunch, a later announcement, reset, presentation deferral, and failed settings saves.

Integration coverage composes real preferences and onboarding persistence with the presentation models. Installed-app journeys cover update-only presentation and dismissal, and prove that completing normal onboarding does not show the update sheet on the next launch. Run the root `test:all` before declaring completion.
