# Release Performance Summary Implementation Plan

> For agentic workers: use superpowers:executing-plans inline, with one final independent review.

**Goal:** Keep a small trustworthy performance table in GitHub releases as benchmark data arrives.

**Architecture:** One reporting module owns tag/source attribution, frozen-result verification, rendering, managed body replacement and idempotent release API updates. The existing release Action invokes it on publication/resume and main pushes containing newly collected history.

**Tech stack:** Node ESM, real Git integration fixtures, existing benchmark history/comparator modules, mocked GitHub boundary.

**Spec:** `docs/superpowers/specs/2026-11-15-release-performance-summary-design.md`.

## Constraints and review focus

- Preserve typed test seams, owned modules, exact source attribution and frozen evaluation.
- Do not substitute newer/unrelated/PR measurements for tagged main source.
- Exclude only generated benchmark data when matching source trees.
- Keep human release text and metadata untouched; guard malformed markers and hostile tag names.
- Missing, failed, regressed, noisy and changed-environment observations must be represented honestly.
- Run affected tooling suites, full tooling tests and full CI before completion.

## Task 1: Source-qualified managed report

- [x] Add failing real-Git tests in `scripts/benchmark-release.test.mjs` for main source selection, data-only tags, changed source, late failed runs, frozen baseline deltas, pending status and managed-body preservation/idempotence.
- [x] Implement `scripts/benchmark-release.mjs` using existing history verification and GitHub API seams.
- [x] Verify red/green cycles and edge cases: no legacy/draft/prerelease edits, unsafe tags, malformed markers, API failures and retries.
- [ ] Commit the tested vertical slice.

## Task 2: Workflow integration and delivery

- [x] Add failing coverage proving the existing release/main-push workflow invokes reporting, including late data and idempotent retries.
- [x] Wire the module into `.github/workflows/release.yml`; use its existing scoped credential. Leave the Cloud collector unchanged.
- [ ] Update deployment documentation and run affected suites, `test:unit:tooling`, and diff checks.
- [ ] Obtain one independent whole-branch review; fix substantive findings with regression coverage.
- [ ] Create/link PR, run full Xcode Cloud `test:all` and release validation, watch and handle failures.
- [ ] Under existing full-auto authorization, merge after checks and review pass. Verify live collector remains healthy; do not publish a release solely for testing.
