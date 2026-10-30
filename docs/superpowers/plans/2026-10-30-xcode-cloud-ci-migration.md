# Xcode Cloud CI migration implementation plan

> **For agentic workers:** Use superpowers:executing-plans to implement these vertical TDD slices.

**Goal:** Prepare manually published releases in GitHub Actions, land generated metadata on main, and run all CI and archive validation in Xcode Cloud.

**Architecture:** The original stable tag (with optional v prefix) stays immutable. Preparation starts at that tag only when its source matches current main. Generated changes and provenance first live on release-preparation/<tag>. An atomic main + release-build/<tag> push is preferred; protected main receives a preparation PR instead. A later main push resumes the handoff only when the merged tree matches the prepared release. Existing branches make retries idempotent. No app tests or archives run in Actions or the local release helper.

**Tech Stack:** Node 24, real Changesets/npm, Git, GitHub CLI/Actions, Xcode Cloud shell hooks, Maestro 2.10.0, Java 17.

**Spec:** User-approved migration requirements in this thread; application seams remain docs/superpowers/specs/2026-09-04-whim-v1-design.md.

## Global constraints

- Preserve original tags and tagged source provenance. Never discard main changes or build stale source silently.
- Both main and release-build/<tag> must contain generated metadata before a release build starts.
- No automatic version PRs on ordinary main pushes; main only resumes an already prepared release.
- Keep test:unit, test:integration, test:e2e and test:all runnable. Execute test:all before handback and report infrastructure failures accurately.
- Never create an actual release/tag to validate this migration.

## Review focus

- Duplicate release/tag events, lost push responses and re-runs must not consume Changesets twice.
- Advancing main and competing versions must stop publication without overwriting work.
- Protected main and squash merges must wait for the actual merged generated tree.
- Cloud hooks must work in isolated action environments and must fail closed on incomplete test/archive coverage.
- GitHub event inputs must remain data, and pending releases must not execute untrusted tagged tooling with write credentials.

### Slice 1: release preparation and main gate

Files: scripts/prepare-cloud-release.mjs, scripts/prepare-cloud-release.test.mjs, scripts/release.test-support.mjs.
Public seam: prepareCloudRelease(root, tag, {run, repository, log}); resumeCloudRelease(root, options).

- [x] Write failing real-Git tests for plain/v tags, generated metadata on both refs, provenance and duplicate events.
- [x] Implement preparation using real version modules and allowlisted generated paths.
- [x] Add failing tests for main advancement, tag mismatch, protected main, squash merges, lost responses, concurrent releases and immutable existing refs; implement each gate.
- [x] Run companion tests after each behavior.

### Slice 2: Cloud CI and release entry points

Files: ios/ci_scripts/ci_*.sh, scripts/xcode-cloud.mjs and companion tests, .github/workflows/release.yml, scripts/release.mjs and companion tests, README.md, docs/xcode-cloud.md.
Public seam: cloud action dispatcher; local release helper only explains the published-release entry point.

- [x] Write failing tests for hook action routing, full suite invocation, native archive checks and dependency setup.
- [x] Implement per-action Node/Java/Maestro bootstrap and full CI in pre-xcodebuild; validate native archive in post-xcodebuild.
- [x] Replace GitHub test workflow with preparation only, with serialized retries and main-merge resumption.
- [x] Replace local release behavior and obsolete tests; document recovery and cloud configuration.
- [x] Run tooling suite, webhook integration and test:all.

### Slice 3: connected setup and delivery

- [x] Inspect and configure existing Cloud Release workflow: prepared branch trigger, test gates, archive validation; retain PR CI in Cloud.
- [x] Record exact access or infrastructure limitations and live configuration status.
- [x] Obtain code review, resolve findings, verify diff, commit, push and create/link a migration PR.

## Execution evidence

- Release and cloud companion slices followed RED → GREEN; final tooling suite: 70 passed.
- Fresh whole-branch review found the concurrent release-build ref race; its regression failed first, then passed with an expected-absence push lease.
- `test:all` ran: unit, integration, system surfaces and Watch integration passed; Maestro iOS driver startup timed out before journeys. Cleanup hung and only this run was terminated. No E2E assertion failure was observed.
- Release trigger and Default PR/main CI settings were saved in App Store Connect; Actions PR creation enabled. No required status was removed. PR #44 is linked to this thread; Apple registered its pending Cloud build.
- Full cloud acceptance and GITHUB_TOKEN release-branch webhook delivery remain infrastructure validation. No real release/tag was created to test them.
