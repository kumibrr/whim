# Performance benchmarks and commit history

**Date:** 2026-11-13

**Status:** Approved by the user on 2026-11-13; implementation in progress

## Intent and decisions

Detect performance regressions in CI and retain a readable benchmark history alongside the app source on `main`.

The user selected four operations: launch readiness, Record-to-capture delay, Stop-to-saved-Note delay, and timeline loading. They requested historical results for commits and selected Git-backed storage on `main`, rather than a separate branch or external service. The measurements belong to development and CI; the installed production app gains no telemetry or reporting.

**Revision:** in response to the user's request to keep execution entirely in Xcode Cloud, replace the proposed GitHub Actions benchmark and publisher jobs with two Xcode Cloud workflows. GitHub remains the Git host. The existing GitHub Actions release-preparation workflow is separate from this feature and is unchanged.

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
- Xcode Cloud build ID, action identity, build number, and run URL; Cloud rebuilds get distinct identities, and separate local runs are explicitly labeled.
- Host runner/architecture/CPU model, macOS version, Xcode build, iOS simulator runtime build and device model, and compiler/build configuration.
- Per-metric sample arrays, sample counts, median, minimum, maximum, and spread; units are milliseconds.
- Selected baseline SHA/run, comparison thresholds, computed deltas, and outcome (`baseline`, `pass`, `regression`, `inconclusive`, or `error`).
- Frozen trusted-history commit SHA, policy content hash, and baseline-record path/content hash used for the native decision; a run with no baseline records that absence against the same snapshot.
- Structured error or missing-metric details when a run cannot complete. An incomplete run cannot pass or become a baseline.

Do not include simulator UDIDs, temporary paths, audio, transcripts, secrets, or arbitrary logs. Derive destination paths from validated SHAs and Cloud UUID build/action identities, never from artifact-supplied filenames. The path's run/attempt component is an opaque validated identity, not an assumed GitHub numeric run ID. Cap artifact size and sample counts; require finite nonnegative timings and all expected metrics for a complete record.

Store results append-only, keyed by source SHA and run/attempt identity. Retrying publication of the same identical record is a no-op; conflicting content under an existing identity is an error. Re-running measurement produces a new record. The measured commit is immutable; a subsequent bot commit records its results.

Generate `benchmarks/README.md` deterministically from the records: a chronological list with source commit links, run links, the five medians, outcome, and baseline. Use source commit order/time and stable run identities rather than completion order. Keep all runs, including failed and superseded ones, available for inspection. No fabricated example results or large XCResult bundles are committed.

## Historical regression policy

Read baseline history from trusted `main`, not from candidate-edited benchmark files. Select the nearest recorded source ancestor with a complete, accepted result and identical measurement protocol, fixture, build configuration, runner architecture/CPU class, OS, Xcode build, simulator runtime, and device model. On a PR, the ancestor must belong to the PR base lineage; candidate or unrelated-branch records never establish its accepted baseline. Store the exact selection in the record.

When the current source itself already has an accepted run, a rerun may compare against that run. Regressing, incomplete, or inconclusive results never advance the accepted baseline. An unknown environment/protocol starts an explicitly labeled baseline series instead of mixing incompatible measurements. Do not call the first observation a regression-free comparison.

Proposed defaults: a median must exceed the baseline by both 20% and 100 ms to be a regression candidate. For a candidate slowdown, collect a second independent batch of ten samples for the affected metric after resetting its fixture. Fail the regression check only when both batches exceed the thresholds. Preserve both batches and their separate verdicts. A disagreement or unstable batch is `inconclusive`, not a passing comparison; initial spread rule is a median absolute deviation greater than 15% of that batch's median. An inconclusive benchmark fails the performance check with a distinct diagnostic and can be rerun; it does not publish a new accepted baseline. Thresholds and the spread rule live in policy and require review to change.

## Xcode Cloud execution

Keep the existing Default/Release workflows responsible for functional CI and release archive validation. Add two benchmark-specific workflows in Xcode Cloud; no GitHub Actions jobs run or publish benchmarks.

1. **Benchmark:** a native Test action using the dedicated benchmark scheme and one fixed iPhone simulator destination. It has no Git-write or App Store Connect API secrets. Disable Auto-cancel Builds. Pin explicit Xcode/macOS settings, record actual versions, and avoid parallel destinations. Recognize this workflow by its configured ID in the shared hooks so its build-for-testing/test-without-building actions do not invoke the functional suite again; existing Default/Release gates retain their current behavior.
2. **Benchmark history:** a small native Build action restricted in Cloud settings to trusted `main` only, with a main-change start condition plus an hourly schedule and manual main-only runs. Its custom script discovers missing source commits, queues measurements, collects completed native result bundles through the App Store Connect API, and appends validated records to Git. It never builds or executes PR code. Functional CI and benchmarks do not need to wait for this publication job to run to report their own failures.

The benchmark XCTest runner attaches raw JSON using `XCTAttachment` with keep-always lifetime before reporting a performance assertion failure. These attachments are part of the **native** Test action's `.xcresult` artifact. Do not rely on a JSON file or nested `xcodebuild` result produced by a custom script becoming a downloadable Cloud artifact, and do not pass temporary files between isolated hooks/actions. Apple exposes `CI_RESULT_BUNDLE_PATH` for test actions; any post-test extraction must use that native result bundle.

Package a bounded read-only set of trusted-main baseline candidates as a native test-bundle resource during build-for-testing, with source ancestry and protocol attribution. Freeze the exact trusted-main history commit and policy at that point, and include their identities in the resource and result attachment. Select the compatible baseline from that frozen history using the actual measurement destination environment, not just the build machine's environment. If a bounded candidate selection omits every compatible ancestor, record the lookup as incomplete rather than falsely declaring a new baseline series; require a complete enough selection to distinguish the two. The native test applies the frozen policy, conditionally collects the second sample batch, attaches all observations, and fails the test on a confirmed regression or inconclusive run. The runner must not use candidate-edited historical files as accepted baseline inputs.

The collector independently recomputes a run's verdict against that same frozen history/policy/baseline, retrieved from trusted Git objects and checked against their hashes. It does not retroactively choose a newer baseline or current-main policy when collecting or retrying a run. Newly completed ancestors affect future measurements only. Persist the originating Cloud metadata and frozen decision context deterministically so replaying publication later produces byte-identical content. Missing/unverifiable context is a distinct collection error, not a rewritten native verdict. An optional later reanalysis would be a separately identified observation and never an overwrite of the original result.

Cloud preserves native result bundles for a limited period (currently 30 days); Git remains the permanent archive. The scheduled collector processes completed runs regardless of success/failure. It can therefore retain regressions even when the test or a post-test script exits nonzero. A canceled/failed build without an attachment becomes an explicit coverage/error record, with no invented samples. History on `main` is eventually updated on the collector's next run rather than necessarily at test completion; manual main-only execution can collect sooner.

## Complete commit coverage and scheduling

Xcode Cloud start conditions operate on branch/PR updates, and PR workflows ordinarily test a temporary merge. Do not interpret one run per update as proof that every intermediate source commit was measured. The trusted history workflow enumerates unrecorded source commits from `main` ancestry and open PR histories after an explicit rollout SHA, and also reconciles source heads observed in existing Cloud build metadata. This catches several commits pushed together and recorded heads from superseded PR updates. Do not claim coverage for source revisions never observed/retrievable by the service.

Queue each eligible source SHA using an immutable execution ref under `benchmark-input/main/<sha>` or `benchmark-input/pr/<number>/<sha>`; configure the credential-free Benchmark workflow's Branch Changes condition to monitor `benchmark-input/`. The ref points directly at the source SHA, so Cloud's native test measures that actual commit instead of a synthetic PR merge. These are execution refs, not a separate history branch: permanent benchmark data still lives exclusively on `main`. They require no new source commits. Their creation is the queue entry; never move/reuse an existing ref with different content, and delete it only after the measurement has been recorded or explicitly closed as an error. Rebuilds of an existing input use Cloud's rebuild/manual controls and get a new Cloud build identity.

Authenticate source context from the collector-created input ref, current Git ancestry/PR metadata, and Cloud API build identity. A PR observation cannot become an accepted main baseline by claiming to be a main run. If the same SHA later belongs to `main`, create a separate main-context measurement before accepting it as a main-line baseline. Do not delete pending inputs when a PR is force-pushed or closed; finish or explicitly record their outcome.

The collector is idempotent: discover source commits, create missing queue refs, and reconcile existing pending/completed inputs on each run. Do not rely on a timestamp high-water mark alone; paginate completed Cloud runs and revisit unfinished jobs so out-of-order completion or a missed scheduled run does not lose results. Bound each sweep, report remaining work, and keep queued refs durable for the next run. Never cancel earlier benchmarks just because a newer commit arrives. Start conditions for existing Default/Release workflows must not match the benchmark-input prefix.

Bootstrap is deliberately ordered. Queue the earliest eligible main source as the seed of a new protocol/environment series, collect its complete stable result, and publish the accepted baseline before scheduling descendants that need it. Along each source lineage, record the previous queued source's outcome before creating the next input ref. PR measurements wait for an available accepted baseline on their base lineage; independent PR lineages may run concurrently once their prerequisite baseline is published. A regression does not advance the baseline, but once recorded it does not prevent measuring the next source against the last accepted ancestor. A build error is recorded as a gap; the next runnable seed is explicitly identified rather than claiming the failed source was compared.

A native observation that unexpectedly finds a new hardware/toolchain series is provisional baseline evidence, not permission to mark a whole backlog as first baselines. Stop scheduling descendants for that series until its eligible main seed is recorded. If work was already in flight against a snapshot with no prerequisite baseline, retain its original observation and schedule a separately identified rerun after the seed is published. Never rewrite the old record, silently accept an uncomparable PR observation, or skip its eventual comparison. An intentionally changed measurement protocol starts a new explicit series; old-protocol numbers cannot supply its seed. This ordering trades throughput and scheduled-workflow latency for meaningful regression coverage from the first comparable descendant.

Classify a source commit as data-only only when its complete diff, including renames/deletions and every parent relevant to the source lineage, changes the two allowlisted generated paths. Policy or code changes must run benchmarks. A data-only result commit has no additional measurements because it executes the same app code; its exclusion is explicit in the index. Do not use a commit-message substring or `[skip ci]` to bypass CI policy. Mixed data/code commits remain eligible. Configure Cloud file/folder start conditions to ignore generated history only, with the same tested classification in hooks as a fallback. The history workflow's scheduled/manual sweeps still run when no source files changed.

Do not claim historical coverage before rollout. A historical commit without the benchmark runner, missing source objects, an expired/missing result bundle, a canceled run, a build failure, or an unavailable toolchain is an explicit coverage gap/error. CI logs and the generated index identify the measured and outstanding source commits. Backfilling a retrievable source SHA or re-collecting a run is a main-only manual history-workflow operation, not a new GitHub workflow.

## Trusted publication and concurrent updates

Only the main-only Benchmark history workflow receives a repository-specific GitHub write credential and an App Store Connect API credential with access to the project's Cloud runs/artifacts. Configure them as secret Cloud environment variables. GitHub is used for Git/API storage access, not Actions execution. Do not assume Xcode Cloud's source-checkout integration grants a reusable push token. Credential provisioning is a rollout requirement, not something to fake or bake into the repository.

Restrict this publisher workflow's branch/manual start conditions to `main` and disable PR/tag/input-ref triggers in Cloud settings, so secrets are never injected into a candidate checkout. A runtime branch/workflow-ID check is additional defense, not the mechanism that isolates credentials. Never build PR code in this workflow, even in a subprocess with a filtered environment.

Download native result bundles through the App Store Connect API into a temporary directory and parse only the expected attachment schema. Never execute candidate scripts, restore candidate caches, or extract archives over trusted executable files. Validate archive entries, bounds, source/build/action attribution, environment metadata, and the frozen policy/history provenance; recompute summaries/verdicts against that same trusted snapshot. Treat failed-run attachments and PR attachments as data. Missing/invalid data is visible as an error, not a passing measurement.

Each publisher performs an optimistic append against fresh `main`, regenerates the index, and pushes a normal fast-forward data-only commit. On an intervening update, fetch the new head, reapply only the new records, regenerate, and retry within a finite bound. Never reset, overwrite another writer's records, or force-push `main`. Surface exhausted retries; the next scheduled/manual sweep retries the same immutable native results idempotently before their retention expires. Do not silently drop earlier results when a newer result arrives first.

Honor branch protection. If bot data commits cannot be pushed, keep the Cloud result bundle, report publication failure, and document the required repository permission/rule configuration instead of disabling protection. A protected-branch PR-based publication mode is a possible follow-up, not a hidden bypass in v1. Alert on repeated collection failures before the native artifact retention window expires.

## Interaction with release preparation and Xcode Cloud

The release tooling currently compares full repository trees and requires the tagged source to match `main`. Recording a result between release preparation and the Cloud archive would invalidate those checks despite unchanged app source. Resolve this as part of the feature, not with a race-prone promise to publish only at certain times.

Introduce a reviewed source-identity comparison that excludes exactly `benchmarks/results/**` and generated `benchmarks/README.md`. The benchmark policy, runner, tests, workflows, fixtures, version files, and provenance stay in source identity. Use it at release handoff and Cloud stale-source checks so benchmark-only appends do not invalidate a prepared release, while any other source change still does. Preserve original tag/provenance checks and original source SHA; never move tags or release-build refs, and never erase benchmark data when preparing/merging a version update. Require ancestry as well as matching source identity where the existing protocol requires main to contain the tagged/prepared source.

Apply the same exact data-only classification to avoid repeating the full custom Xcode Cloud test/archive gates for a benchmark-data-only main update. The native Cloud Build action may still run; mixed changes and every release-build action retain the full gates. Existing stable test entry points remain runnable.

Generated benchmark files must never be bundled as app resources or executed by release/product tooling. Add regressions proving an allowlisted result append is tolerated while a policy/code/provenance change is rejected, including concurrent result publication during release preparation and verification.

## Verification and acceptance

Follow AGENTS.md: vertical test-driven slices, failing companion tests before behavioral implementation, owned modules composed through approved seams, and boundary fakes only. Keep root unit/integration/E2E commands intact and run `npm run test:all` before declaring implementation complete.

- Unit/tooling behavior: schema and summary validation, units, median/spread, combined tolerance boundaries, second-batch decisions, incomplete samples, environment matching, untrusted baseline exclusion, attribution, deterministic history/index, and narrowly scoped data-only classification.
- Integration behavior: run collection/export against an actual XCResult attachment; real local bare Git remotes for append/no-op/conflict/reordered/concurrent publication and immutable execution-ref scheduling; real release preparation and verification with benchmark-only changes versus actual source changes; mocked App Store Connect/GitHub API boundaries for paginated discovery, failed-run artifacts, retention gaps, source attribution, and queue reconciliation. Verify that publisher secrets cannot be available in the configured measurement workflow.
- Installed-app behavior: compile/run all five measurements, verify their stated start/end observations against fixtures, and show that an intentional delay at the relevant test boundary is recorded and causes the comparator to fail. Remove the intentional delay from the final source.
- CI acceptance: after merge/enablement, real Cloud input-ref creation, a native benchmark Test action, API download of its attachment, and a trusted collector must produce a source-attributed result and index on `main`; a controlled slowdown must fail without losing its record; a generated-data-only update must not recursively benchmark itself. Verify multi-commit pushes, PR source-SHA identity, out-of-order completion, credential isolation, and scheduled/manual replay before claiming all-commit coverage. Keep local verification and live CI acceptance distinct.
- Physical acceptance: record device/OS and separately measure real microphone onset and stop/preservation; simulator results do not close those acceptance cases.

## Implementation discretion and rollout

The builder may choose focused file/module names, XCTest attachment plumbing, existing fixture extensions, and the supported exact Cloud Xcode/macOS/destination settings after checking availability. They must preserve the measurement boundaries, provenance, publication trust separation, native artifact transport, and exact generated-path exclusions above. Any change to those boundaries requires revisiting this design.

Do not backfill invented data, activate a public site, change distribution signing, or push code directly to `main` during local implementation. Prepare and verify the implementation in the existing worktree. Live history begins only when the workflows are reviewed and enabled on `main` with publication permissions; the feature is not deployed merely because local tests pass.

## References

- Existing v1 interfaces and testing policy: `CONTEXT.md`, `AGENTS.md`, and `docs/superpowers/specs/2026-09-04-whim-v1-design.md`.
- Existing startup boundaries: `docs/startup-flow.md`.
- Existing CI/release behavior: `docs/xcode-cloud.md`, `scripts/xcode-cloud.mjs`, and `scripts/prepare-cloud-release.mjs`.
- [Apple XCTest performance tests](https://developer.apple.com/documentation/xctest/performance-tests).
- [Apple custom build scripts](https://developer.apple.com/documentation/xcode/writing-custom-build-scripts), including hook isolation, custom-file artifact limitations, and post-xcodebuild execution after native failures.
- [Apple Cloud environment variables](https://developer.apple.com/documentation/xcode/environment-variable-reference), including build identity and `CI_RESULT_BUNDLE_PATH`.
- [Apple Cloud start conditions](https://developer.apple.com/documentation/xcode/configuring-start-conditions), including scheduled/manual starts and temporary PR merges.
- [Apple Cloud workflow reference](https://developer.apple.com/documentation/xcode/xcode-cloud-workflow-reference), including Auto-cancel Builds and secret workflow variables.
- [Apple Cloud native artifact retention](https://developer.apple.com/documentation/xcode/configuring-your-first-xcode-cloud-workflow).
- [Apple Cloud artifacts API](https://developer.apple.com/documentation/appstoreconnectapi/ciartifact/attributes-data.dictionary), including `RESULT_BUNDLE` artifacts and their download URLs.
