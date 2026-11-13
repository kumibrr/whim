# Performance Benchmarks Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Measure iPhone performance in Xcode Cloud, gate regressions, and retain source-attributed results on main.

**Architecture:** A credential-free native benchmark Test action writes JSON XCTest attachments. A separate trusted main-only Cloud collector schedules immutable source refs, reads native results through the App Store Connect API, and appends validated records and an index to Git. Reviewed source identity ignores only generated benchmark history.

**Tech Stack:** Node ESM/node:test, Swift/XCTest/XCUIAutomation, Xcode Cloud hooks, Git, App Store Connect/GitHub REST APIs.

**Spec:** `docs/superpowers/specs/2026-11-13-performance-benchmarks-design.md` (approved by the user on 2026-11-13).

## Global Constraints

- Metrics: launch.empty, launch.populated, record.populated, stop.populated, timeline.populated; 1,000 Notes for populated fixtures.
- Two warmups, ten samples, median slowdown greater than both 20% and 100 ms, confirmed in a second batch; median absolute deviation above 15% means inconclusive.
- Real owned modules; fake only audio/permissions/network system boundaries. Required Live Activity remains in capture.
- Freeze trusted history/policy/baseline per native run; do not change a decision during collection or publication replay.
- Native XCTest attachments are the artifact transport; custom-script temporary files are not durable Cloud artifacts.
- No benchmark GitHub Actions, no credentials in candidate/test workflows, no force pushes, no writes to shared main during local implementation.
- Only `benchmarks/results/**` and generated `benchmarks/README.md` are data-only. Release tags/provenance/code checks stay strict otherwise.
- Run affected suites for every slice and `npm run test:all` before claiming completion. Live Cloud deployment/credential provisioning remains distinct from local verification.

## Review Focus

- Policy/baseline changes between test completion and collection must not rewrite verdicts (Tasks 1, 4).
- Incomplete or malformed artifacts must not become passing baselines (Tasks 1, 4).
- Concurrent result appends must preserve both writers and release source identity (Task 2).
- Multiple source commits and first-baseline scheduling must not silently lose comparisons (Task 4).
- Stale saved feedback and fixture setup must not falsely end/inflate UI intervals (Task 3).

## File Structure

- `scripts/benchmark-metrics.mjs` and companion tests: policy, sample statistics, validation, deterministic verdicts.
- `scripts/benchmark-history.mjs` and companion tests: frozen Git snapshots, append-only history/index, source identity, publication retries.
- `scripts/benchmark-cloud.mjs` and companion tests: Cloud role dispatch, API discovery, queue, native-result collection, trusted attribution.
- `benchmarks/policy.json`, `benchmarks/support/BenchmarkMetrics.swift` and companion tests: reviewed policy and native decision support; never bundled in the app.
- `e2e/iphone/Performance.e2e.test.swift`: native installed-app measurements; dedicated Xcode test target/scheme.
- `packages/WhimCore/.../AppComposition/BenchmarkFixture.swift` and companion integration test: DEBUG-only isolated seeded app state through the real store.
- Existing manifests, colocation/release checkers, release identity tooling, Cloud hooks, test scripts, and CI documentation: wire the new seams without removing existing gates.

### Task 1: Validated measurements and native policy

**Interfaces:** `summarize(samples, policy)`, `evaluateMetric(batches, baseline, policy)`, `evaluateRun(observation, baseline, policy)`, `validateObservation(value, policy)`. Swift `BenchmarkMetrics` implements the same statistics/decision contract with shared conformance vectors.

- [ ] Add failing companion tests for exact combined thresholds, spread, confirmation, missing/negative/nonfinite samples, metric completeness, and deterministic evaluation.
- [ ] Run `node --test scripts/benchmark-metrics.test.mjs`; observe missing-module failure.
- [ ] Implement policy/validation/comparison and native support; share JSON conformance cases between Node and Swift tests.
- [ ] Run affected Node and Swift support suites; verify agreement on all vectors.
- [ ] Commit the verified slice.

### Task 2: Permanent history and release-compatible source identity

**Interfaces:** `readHistory(root, ref)`, `freezeSnapshot(root, source, historyRef)`, `appendResults(root, records)`, `publishResults(root, records, options)`, `sourceTree(root, ref)`, `isBenchmarkData(path)`. Use existing `runCommand(exe,args,{cwd,capture})` at Git/process boundaries.

- [ ] Add failing real-Git tests for immutable records, deterministic README, identical replay, conflicting replay, reordered results and an intervening main push.
- [ ] Add release regressions: result-only appends preserve release validity; code/policy/provenance changes fail; release preparation never drops existing history.
- [ ] Implement frozen snapshot/hash validation, optimistic append/push, and exact generated-path source identity; integrate only the needed release comparisons.
- [ ] Run the history suite and complete release-tooling regressions.
- [ ] Commit the verified slice.

### Task 3: Seeded native app performance tests

**Interfaces:** DEBUG `BenchmarkFixture` validates a UUID-isolated fixture request and seeds exactly 0/1000 Notes using real WhimStore and files; native app launch uses existing typed composition. `WhimPerformanceTests` writes complete raw observations as a keep-always XCTest JSON attachment.

- [ ] Add failing fixture integration coverage for deterministic population, isolation, idempotent setup, and invalid fixture inputs.
- [ ] Add native measurement tests first; add dedicated test target/scheme and source membership checks. The expected preimplementation failure is missing fixture/ready state.
- [ ] Implement minimum fixture composition, metrics support, native input snapshot build phase, real accessibility observations, and local `test:performance` runner.
- [ ] Run fixture integration, support conformance, target/source checkers, optimized native tests, and a controlled-delay regression; preserve native XCResult for collector integration.
- [ ] Commit the verified slice.

### Task 4: Cloud scheduling and trusted collection

**Interfaces:** `benchmarkCloudPhase(phase, root, {env,run,request})`; workflow IDs identify native measurement versus main-only publisher. GitHub/ASC clients have injectable HTTP boundaries. Collector inputs are native artifact/build metadata plus frozen trusted Git context; outputs are validated immutable records and input refs.

- [ ] Add failing hook tests for credential-free measurement actions, main-only publisher, unchanged Default/Release gates, generated-only updates, and original test-failure propagation.
- [ ] Add API-boundary integration tests for paginated/out-of-order jobs, immutable input refs, baseline-first scheduling, failed-run attachment collection, wrong source/build identities, expired/malformed artifacts, and publication replay after policy changes.
- [ ] Implement scoped API clients/JWT auth, native attachment extraction with archive validation, queue/reconciliation and fixed-snapshot verdict verification. Fail visibly on partial collection rather than dropping it.
- [ ] Wire hooks per role; do not install functional E2E dependencies or keychain state in benchmark-only roles. Add collector-only build scheme, workflow setup instructions, and explicit secret names.
- [ ] Run Cloud tooling/history/metrics suites and extract the actual Task 3 XCResult attachment through the collector seam.
- [ ] Commit the verified slice.

### Task 5: Full verification and review

- [ ] Update physical acceptance and Cloud setup/rollout documentation, mark the approved design, and document actual checks without claiming live deployment.
- [ ] Run root `test:all`, `test:performance`, release fixture/source checks and whitespace validation. Diagnose failures; add regressions before fixes.
- [ ] Have one fresh reviewer inspect the whole implementation against the plan/spec. Fix consequential findings with reproducing tests.
- [ ] Commit verified changes, report results and any outstanding live Cloud configuration/credential prerequisites. Do not push to main or create a release.
