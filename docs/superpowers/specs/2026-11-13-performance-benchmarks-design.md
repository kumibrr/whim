# Performance benchmarks and commit history

**Date:** 2026-11-13

**Status:** Proposed; implementation awaits design approval

## Intent and decisions

Detect performance regressions in CI and retain a readable benchmark history alongside the app source on `main`.

The user selected four operations: launch readiness, Record-to-capture delay, Stop-to-saved-Note delay, and timeline loading. They requested historical results for commits and selected Git-backed storage on `main`, rather than a separate branch or external service. The measurements belong to development and CI; the installed production app gains no telemetry or reporting.

The implementation choices below are the author's proposals for approval, rather than choices already made by the user.

## Approaches considered

1. **Fixed budgets only.** Cheap to execute, but no durable commit history and smaller slowdowns can remain within a loose limit. Retain a configurable tolerance policy, but use historical comparisons instead of absolute budgets as the primary regression gate.
2. **Rebuild the base and candidate in every run.** Gives a same-machine comparison, at the cost of extra builds and no persistent record by itself. Not selected as the initial gate; a fresh run of an ancestor can be requested when investigating environment drift.
3. **Historical measurements in Git.** Retain raw samples and compare compatible ancestral results. A dedicated branch avoids source-branch traffic; an external service offers a hosted dashboard. The user selected storage on `main` for discoverability and to keep source, tests, and results together.

## Scope

- Benchmark the compiled iPhone app at the existing installed-application and accessibility-visible UI seams, using real presentation models, WhimService, SQLite, and audio files together.
- Substitute deterministic playable audio, granted permissions, isolated preferences, and offline networking only at system boundaries. Keep the required Live Activity path in the measured recording workflow.
- Cover a completed-onboarding state with an empty store and a realistic fixed store of 1,000 Notes. No real user data or credentials enter fixtures or result files.
- Retain each run, including regressions and explicit incomplete/error outcomes. Never invent timings for a failed or unexecuted sample.
- Provide a local `npm run test:performance` entry point and a CI regression check.

Watch performance, real microphone onset, locked-device OS shortcut dispatch, background scheduling, CPU/memory profiling, and a hosted dashboard are outside this first implementation. Simulator fixture results must be labeled as such; they do not prove physical capture latency. Add physical acceptance instructions for the closest hardware measurements.

## Measurement definitions

Use a dedicated iPhone XCUI test bundle and shared scheme, with existing source/test colocation rules extended to recognize its installed-app tests. A monotonic clock in the test harness measures these intervals in milliseconds:

| Metric ID | Start | End | Fixture |
| --- | --- | --- | --- |
| `launch.empty` | Immediately before launching a terminated app process | Record control exists, is enabled, and is hittable | Empty, onboarding complete |
| `launch.populated` | Same launch boundary | Same Record readiness boundary | 1,000 Notes, onboarding complete |
| `record.populated` | Immediately before tapping Record | Recording UI appears after successful recording-service start; Stop is enabled | 1,000 Notes, deterministic audio |
| `stop.populated` | Immediately before tapping Stop | The normal `Note saved` feedback appears and capture has ended | Active Recording Session over the populated fixture |
| `timeline.populated` | Immediately before opening history through the normal UI | History is visible and its expected most recent Note is rendered | 1,000 Notes |

These are automation-observed response times, including interaction and accessibility synchronization overhead. `record.populated` measures the fixture recording workflow through the UI, not the first physical encoded microphone buffer. For Stop, begin with no stale saved feedback (use a fresh process per capture sample), observe the normal `Note saved` feedback that `IPhoneModel.stopRecording()` sets only after successful finalization, then verify the newly saved Note through history outside the interval. Seeing an existing row or merely hiding the recorder never completes the Stop measurement. Stop does not wait for a webhook response or on-device transcription.

Use the app's real history opening/loading behavior. Do not bypass the normal projection with a benchmark-only fast path. Fixture seeding, onboarding, prompts, build/install time, navigation needed only to inspect an already completed operation, and cleanup are outside the timed boundary. Existing `record-and-review.e2e.test.yaml` already exercises the saved feedback followed by history; benchmark these same observations without adding a new observation seam.

Initialize fixture state in an untimed setup launch, then terminate before launch samples. Keep the seed and workload stable across iterations; remove newly captured Notes outside the measurement. A cold launch here means a new app process, not a flushed OS/disk cache. Do not disable real app animations to improve the numbers.

Proposed initial protocol: two untimed warmups and ten recorded samples per metric. Execute serially with no competing E2E suite. Build optimized Debug (`-O`, retaining DEBUG fixture boundaries) and record that exact configuration. Benchmark launch switches and fixture assets must remain absent from distribution Release executables under the existing fixture gate.

## Results on main

```text
benchmarks/
  policy.json
  README.md
  results/<source-sha>/<run-id>-<attempt>.json
```

`policy.json` is reviewed source configuration. Only `results/**` and the generated `README.md` are benchmark data. Tests, scripts, policy, fixtures, and workflows are never classified as data-only changes.

Each versioned JSON record contains:

- Schema version, measurement-protocol version, and deterministic fixture revision.
- Exact measured source SHA and parent SHA(s), source branch/PR, source commit time, and measurement time.
- CI run ID, run attempt, and run URL; separate local runs are explicitly labeled.
- Host runner/architecture/CPU model, macOS version, Xcode build, iOS simulator runtime build and device model, and compiler/build configuration.
- Per-metric sample arrays, sample counts, median, minimum, maximum, and spread; units are milliseconds.
- Selected baseline SHA/run, comparison thresholds, computed deltas, and outcome (`baseline`, `pass`, `regression`, `inconclusive`, or `error`).
- Structured error or missing-metric details when a run cannot complete. An incomplete run cannot pass or become a baseline.

Do not include simulator UDIDs, temporary paths, audio, transcripts, secrets, or arbitrary logs. Derive destination paths from validated SHAs and numeric run identities, never from artifact-supplied filenames. Cap artifact size and sample counts; require finite nonnegative timings and all expected metrics for a complete record.

Store results append-only, keyed by source SHA and run/attempt identity. Retrying publication of the same identical record is a no-op; conflicting content under an existing identity is an error. Re-running measurement produces a new record. The measured commit is immutable; a subsequent bot commit records its results.

Generate `benchmarks/README.md` deterministically from the records: a chronological list with source commit links, run links, the five medians, outcome, and baseline. Use source commit order/time and stable run identities rather than completion order. Keep all runs, including failed and superseded ones, available for inspection. No fabricated example results or large XCResult bundles are committed.

## Historical regression policy

Read baseline history from trusted `main`, not from candidate-edited benchmark files. Select the nearest recorded source ancestor with a complete, accepted result and identical measurement protocol, fixture, build configuration, runner architecture/CPU class, OS, Xcode build, simulator runtime, and device model. On a PR, the ancestor must belong to the PR base lineage; candidate or unrelated-branch records never establish its accepted baseline. Store the exact selection in the record.

When the current source itself already has an accepted run, a rerun may compare against that run. Regressing, incomplete, or inconclusive results never advance the accepted baseline. An unknown environment/protocol starts an explicitly labeled baseline series instead of mixing incompatible measurements. Do not call the first observation a regression-free comparison.

Proposed defaults: a median must exceed the baseline by both 20% and 100 ms to be a regression candidate. For a candidate slowdown, collect a second independent batch of ten samples for the affected metric after resetting its fixture. Fail the regression check only when both batches exceed the thresholds. Preserve both batches and their separate verdicts. A disagreement or unstable batch is `inconclusive`, not a passing comparison; initial spread rule is a median absolute deviation greater than 15% of that batch's median. An inconclusive benchmark fails the performance check with a distinct diagnostic and can be rerun; it does not publish a new accepted baseline. Thresholds and the spread rule live in policy and require review to change.

## CI and complete commit coverage

**Proposed CI placement:** add a benchmark-specific GitHub Actions macOS workflow, while Xcode Cloud continues to run the existing full functional suites and release archive gates. A separate trusted GitHub publisher can persist benchmark artifacts with the built-in GitHub token; PR builds need neither a main-write credential nor an additional secret in Xcode Cloud. This is an additional benchmark runner, not a migration of functional CI.

Pin the macOS runner and explicit Xcode selection to a supported toolchain, and use the repository's compatible simulator model selection. The image version and actual selected tools are recorded. A machine-image update can create a new baseline series, never a misleading cross-machine regression.

On pushes to `main` and PR updates, enumerate every newly introduced source commit, not only the event's final SHA. First PR runs enumerate the PR's commits. Handle force-pushes through the new base-to-head ancestry. Benchmark each eligible commit after this capability is introduced, retain per-commit outcomes, and continue collecting the rest of a push after an earlier commit regresses. Do not cancel older runs just because a newer push arrives. Run benchmarks serially on a worker; split work into explicit batches if platform job-duration limits require it. A PR benchmark measures its actual source SHA, not a synthetic merge SHA mislabeled as the source.

Classify a commit as data-only only when its complete diff, including renames/deletions and every parent relevant to the source lineage, changes the two allowlisted generated paths. Policy or code changes must run benchmarks. A data-only result commit has no additional measurements because it executes the same app code; its exclusion is explicit in the index. Do not use a commit-message substring or `[skip ci]` to bypass the full CI policy. Mixed data/code commits remain eligible.

Do not claim historical coverage before rollout. A historical commit without the benchmark runner, a canceled run, a build failure, or an unavailable toolchain is an explicit coverage gap/error, not a zero or a skipped passing result. Manual dispatch supports measuring a source SHA or retrying a failed collection. CI logs identify each intended commit and its outcome.

The measurement workflow uploads its result artifact even when the performance check fails. Keep the workflow's failure visible after export. An independent publisher also runs on failed measurement workflows, so regressions remain in the permanent history.

## Trusted publication and concurrent updates

Use a separate `workflow_run` publisher running trusted code from the current `main` branch with `actions:read` and narrowly scoped `contents:write`. Download records as data into a temporary directory; never execute candidate scripts, restore candidate caches, or unpack artifacts over trusted executable files in the privileged job. Validate source/run attribution against the originating workflow event/API and recompute summaries/verdicts against trusted policy and history. Fork/PR records remain attributed as candidate observations and can never become main-line accepted baselines by their claimed metadata alone.

For complete multi-commit artifacts, authenticate the commit set from GitHub event/API ancestry; do not require every record's SHA to equal only the workflow head, and do not accept arbitrary SHAs supplied by an artifact. A result record must correspond to a declared target in that authenticated set.

Avoid a single GitHub concurrency group as the only queue: pending runs can be replaced even when cancellation is disabled. Each publisher performs an optimistic append against fresh `main`, regenerates the index, and pushes a normal fast-forward data-only commit. On an intervening update, fetch the new head, reapply only the new records, regenerate, and retry within a finite bound. Never reset, overwrite another writer's records, or force-push `main`. Surface exhausted retries and support idempotent manual replay from the originating run artifact. Do not silently drop an earlier result when a newer result arrives first.

Honor branch protection. If bot data commits cannot be pushed, retain the measurement artifact and report publication failure; document the required repository permission/rule configuration instead of disabling protection. A protected-branch PR-based publication mode is a possible follow-up, not a hidden bypass in v1.

## Interaction with release preparation and Xcode Cloud

The release tooling currently compares full repository trees and requires the tagged source to match `main`. Recording a result between release preparation and the Cloud archive would invalidate those checks despite unchanged app source. Resolve this as part of the feature, not with a race-prone promise to publish only at certain times.

Introduce a reviewed source-identity comparison that excludes exactly `benchmarks/results/**` and generated `benchmarks/README.md`. The benchmark policy, runner, tests, workflows, fixtures, version files, and provenance stay in source identity. Use it at release handoff and Cloud stale-source checks so benchmark-only appends do not invalidate a prepared release, while any other source change still does. Preserve original tag/provenance checks and original source SHA; never move tags or release-build refs, and never erase benchmark data when preparing/merging a version update. Require ancestry as well as matching source identity where the existing protocol requires main to contain the tagged/prepared source.

Apply the same exact data-only classification to avoid repeating the full custom Xcode Cloud test/archive gates for a benchmark-data-only main update. The native Cloud Build action may still run; mixed changes and every release-build action retain the full gates. Existing stable test entry points remain runnable.

Generated benchmark files must never be bundled as app resources or executed by release/product tooling. Add regressions proving an allowlisted result append is tolerated while a policy/code/provenance change is rejected, including concurrent result publication during release preparation and verification.

## Verification and acceptance

Follow AGENTS.md: vertical test-driven slices, failing companion tests before behavioral implementation, owned modules composed through approved seams, and boundary fakes only. Keep root unit/integration/E2E commands intact and run `npm run test:all` before declaring implementation complete.

- Unit/tooling behavior: schema and summary validation, units, median/spread, combined tolerance boundaries, second-batch decisions, incomplete samples, environment matching, untrusted baseline exclusion, attribution, deterministic history/index, and narrowly scoped data-only classification.
- Integration behavior: run collection/export against an actual XCResult attachment; real local bare Git remotes for append/no-op/conflict/reordered/concurrent publication; real release preparation and verification with benchmark-only changes versus actual source changes; mocked GitHub API boundary for publisher events/artifacts.
- Installed-app behavior: compile/run all five measurements, verify their stated start/end observations against fixtures, and show that an intentional delay at the relevant test boundary is recorded and causes the comparator to fail. Remove the intentional delay from the final source.
- CI acceptance: after merge/enablement, a real benchmark run and trusted publisher must produce a source-attributed result and index on `main`; a controlled slowdown must fail without losing its record; a generated-data-only update must not recursively benchmark itself. Keep local verification and live CI acceptance distinct.
- Physical acceptance: record device/OS and separately measure real microphone onset and stop/preservation; simulator results do not close those acceptance cases.

## Implementation discretion and rollout

The builder may choose focused file/module names, XCTest attachment plumbing, existing fixture extensions, and the supported exact runner/Xcode version after checking availability. They must preserve the measurement boundaries, provenance, publication trust separation, and exact generated-path exclusions above. Any change to those boundaries requires revisiting this design.

Do not backfill invented data, activate a public site, change distribution signing, or push code directly to `main` during local implementation. Prepare and verify the implementation in the existing worktree. Live history begins only when the workflows are reviewed and enabled on `main` with publication permissions; the feature is not deployed merely because local tests pass.

## References

- Existing v1 interfaces and testing policy: `CONTEXT.md`, `AGENTS.md`, and `docs/superpowers/specs/2026-09-04-whim-v1-design.md`.
- Existing startup boundaries: `docs/startup-flow.md`.
- Existing CI/release behavior: `docs/xcode-cloud.md`, `scripts/xcode-cloud.mjs`, and `scripts/prepare-cloud-release.mjs`.
- [Apple XCTest performance tests](https://developer.apple.com/documentation/xctest/performance-tests).
- [GitHub workflow_run and artifact handoff](https://docs.github.com/en/actions/reference/workflows-and-actions/events-that-trigger-workflows#workflow_run), including its warning about untrusted artifacts in privileged workflows.
- [GitHub macOS runner inventory](https://github.com/actions/runner-images/blob/main/images/macos/macos-26-Readme.md); actual runner/tool versions must be pinned and recorded at implementation time.
