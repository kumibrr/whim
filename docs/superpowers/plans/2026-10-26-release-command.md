# Release Command Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Provide one local command for validated app versioning and publication to GitHub, handing the version tag to Xcode Cloud.

**Architecture:** A Node ESM entry point coordinates the existing npm, Git, and GitHub CLI interfaces. A separate version-preparation entry point composes Changesets, Xcode version synchronization, and npm lockfile refresh. External command execution is the controlled system boundary in tests; real local Git repositories and real version-preparation modules prove outcomes.

**Tech Stack:** Node ESM, node:test, Changesets, Git, GitHub CLI, existing macOS/Xcode runners.

**Spec:** docs/superpowers/specs/2026-10-26-release-command-design.md

## Global Constraints

- Implementing it must not release a new app version or create a tag.
- Use Node ESM and the repository's existing test runner; add no dependency.
- Both checks must succeed before creating a release commit or pushing anything.
- Use a normal fast-forward push; never force-push.
- App Store submission and the documented physical acceptance checks remain manual.

## Review Focus

- Authentication or remote lookup failures must stop before version preparation.
- A reused tag must never move or trigger another release.
- Concurrent edits or a moving main must prevent unintended publication.
- Failed validation must preserve prepared files without a commit or remote change.
- GitHub publication failure after a successful push must offer publication-only recovery.

---

### Task 1: Complete version preparation

**Files:** Create `scripts/prepare-release-version.mjs` and its companion test; modify `package.json`.

**Interfaces:** Export `prepareReleaseVersion(root, run)`; `run(command, args, options)` returns command stdout or throws. CLI uses the working directory. Produce consistent app manifest, changelog, Xcode versions, and npm lockfile through `npm run release:version`.

- [x] Write a fixture test invoking real Changesets and version synchronization; assert version, changelog, consumed Changeset, every Xcode version, and workspace lockfile version agree.
- [x] Run `node --test scripts/prepare-release-version.test.mjs`; expect failure before implementation.
- [x] Implement the entry point and update `release:version` to invoke it.
- [x] Run the companion suite; expect all tests passing, including a failed command stopping preparation.
- [x] Commit the version-preparation slice.

### Task 2: Release orchestration and recovery

**Files:** Create `scripts/release.mjs`, `scripts/release.test.mjs`; modify `package.json` and `README.md`.

**Interfaces:** Export `release(root, {run, platform, log})`; CLI invokes it in the working directory and exits nonzero on failure. Use the existing `release:version`, `test:all`, and `verify:release` interfaces. Add `npm run release`.

- [x] Write the happy-path fixture test first: real local Git remote, controlled Apple/GitHub processes, real version preparation; assert committed version files, atomic main/tag publication, changelog release notes, and no unrelated files.
- [x] Run the test; expect failure before implementation.
- [x] Implement the smallest successful command flow.
- [x] Add and run failing cases in vertical slices for dirty/detached/diverged checkout, platform/dependency/auth failures, no Changesets, reused tag, invalid version, failed tests/archive, concurrent edits/main movement, and rejected push/publication recovery. Implement each guard after observing its failure.
- [x] Document prerequisites, successful flow, failure recovery, cloud handoff, and manual acceptance/submission.
- [ ] Run `npm run test:unit:tooling`; expect all passing. Run `npm run test:all` with external build storage; expect all suites passing. Verify a clean Release archive with the existing archive command.
- [x] Commit the command and documentation.

### Task 3: Final review

**Files:** Review the complete branch against the design. Verification exposed fixes in `scripts/terminate-process-tree.mjs` and its companion test, `scripts/restart-e2e-simulator.mjs` and its companion test, `scripts/test-iphone-e2e.sh`, `e2e/iphone/flows/clean-launch.yaml`, and `e2e/iphone/onboarding.e2e.test.yaml`. These address interrupted-run cleanup, fresh simulator readiness, and an impossible fixed-footer centering requirement; app behavior is unchanged.

- [x] Obtain the fresh whole-branch review required by executing-plans, carrying the spec, plan, and review focus.
- [ ] Reproduce material findings with failing companion tests, fix, and rerun affected checks; rerun full checks if implementation changes.
- [ ] Confirm no real version bump, tag, or GitHub release was created, inspect the final diff, and report the command and verification results.
