# iPhone performance benchmarks

The benchmark runs and publishes entirely in Xcode Cloud. GitHub provides repository storage and API access; no GitHub Actions benchmark job is involved. The existing release-preparation Action remains independent.

Native scheme `WhimPerformanceTests` measures the installed app serially using `DebugBenchmark`: optimized Swift (`-O`), DEBUG hardware fixtures, arm64, real persistence, normal animation and required Live Activity behavior. It measures these public observations:

| Metric | Start | End | Fixture |
| --- | --- | --- | --- |
| `launch.empty` | New process launch | Record is enabled and hittable | 0 Notes |
| `launch.populated` | New process launch | Record is enabled and hittable | 1,000 Notes |
| `record.populated` | Record tap | Stop is enabled and hittable | 1,000 Notes |
| `stop.populated` | Stop tap | New `Note saved` feedback and Record ready | 1,000 Notes |
| `timeline.populated` | History tap | History and newest seeded Note are accessible | 1,000 Notes |

The fixture isolates SQLite, audio files, credentials and preferences by UUID. Seeding, onboarding/update acknowledgement, installation and cleanup are untimed. Stop verifies and deletes its new Note after timing, preserving the workload. Audio input, permissions and external connectivity are deterministic system boundaries. These measurements do not establish physical microphone onset, release-device performance, waveform playback readiness, or network delivery latency.

`benchmarks/policy.json` defines two warmups and ten samples per metric. A median slowdown must exceed **both 20% and 100 ms**, then recur in a second ten-sample batch, to fail as a regression. Median absolute deviation above 15% produces an inconclusive failure. Failed/incomplete and inconclusive runs cannot advance a baseline. Baselines must be accepted main-context ancestors with the same protocol, fixture and complete environment metadata. A new series can seed on main; an uncomparable PR result remains provisional and fails its native gate.

## Execution and history

1. The trusted history workflow enumerates main ancestry from the configured rollout SHA and the current histories of open PRs, plus original PR heads observed in this product’s Cloud build metadata (including superseded and closed PRs). New PR work must have a commit time at or after the rollout commit time; already retained pending work survives a later cutoff. It preserves observed PR backlog commits under `benchmark-queue/pr/<number>/<sha>` before scheduling, so subsequent closure/force-push cannot discard them. Queue refs contain source commits, not benchmark data, and do not match any build start condition.
2. It creates one immutable `benchmark-input/main/<sha>` or `benchmark-input/pr/<number>/<sha>` ref per ready lineage. Main seeds first; PRs wait for an accepted ancestor baseline. The native workflow tests the exact source SHA, rather than a temporary PR merge. Earlier work is never canceled for a newer commit.
3. Build-for-testing freezes trusted main history, policy hash and candidate baselines in a test-bundle resource. The test destination selects the matching environment and emits a keep-always `whim-benchmark-observation.json` XCTest attachment, including partial samples on failure. Source/Node are not required during test-without-building.
4. On its next sweep, the history workflow downloads Apple's native `.xcresult` artifacts, validates attribution and bounded archive/JSON contents, recomputes the frozen decision, and appends the result to `benchmarks/results/<source-sha>/<cloud-build-uuid>.json`. It regenerates [the benchmark list](../benchmarks/README.md) and pushes a normal data-only commit to main. Concurrent main updates are fetched and retried without force pushes.
5. Input/backlog refs are removed only after recording a terminal outcome. Automatic input deletion additionally requires a result newly collected in that sweep; an old published result cannot close a newly recreated input while its new Cloud run is not yet visible. A provisional PR input is retained; when matching main evidence becomes available the collector starts a fresh native run against that ref. A newer in-flight run takes precedence over older completed runs during reconciliation.

Missing-runner coverage records use a `-coverage-main` or `-coverage-pr-<number>` filename suffix: their UUID identifies the real collector build, and the suffix distinguishes source contexts without inventing a measurement build.

Each result retains raw milliseconds, summaries, environment, source parents/time, run identity, frozen history/policy/baseline hashes and verdict. Publication replay is immutable and idempotent. No audio, transcripts, secrets or simulator UDIDs enter history. Source revisions never observed or no longer retrievable are outside coverage; this is not retrospective coverage before rollout.

Build failures, historical sources without a runner, missing artifacts after a one-hour availability grace period, and invalid artifacts become explicit error records with no invented timings. Download/API failures remain pending and fail the collector visibly. A pending input with no Cloud run raises a configuration error. The next scheduled/manual sweep retries unfinished work. Cloud artifact retention is finite; monitor collector failures rather than treating the permanent Git index as proof that every queued source has finished.

Generated-data-only commits are excluded from benchmarking and the Default workflow's custom gates to prevent recursion. The exact allowlist is `benchmarks/results/**` and generated `benchmarks/README.md`. Policy, scripts, tests and mixed changes always count as source. Release source comparisons use this same narrow exclusion and preserve benchmark history during version preparation; tag and provenance checks remain strict.

## Configure two Cloud workflows

These settings are a deployment step after merging the implementation. Repository files alone do not create or enable Cloud workflows. Use workspace `ios/Whim.xcworkspace`. [Apple describes the separate native Test phases](https://developer.apple.com/documentation/xcode/configuring-your-xcode-cloud-workflow-s-actions) and [workflow secret/start-condition settings](https://developer.apple.com/documentation/xcode/xcode-cloud-workflow-reference).

**Benchmark**

- One native iOS **Test** action using scheme `WhimPerformanceTests`, scheme configuration `DebugBenchmark`, one fixed supported arm64 iPhone simulator/runtime, and a fixed Xcode/macOS image. Disable parallel test execution and Auto-cancel Builds. Keep this destination/toolchain unchanged within a series.
- Branch Changes: names beginning with `benchmark-input/`, all files. No PR, main, tag or schedule triggers. Manual runs/rebuilds must also select an input ref.
- Add `WHIM_BENCHMARK_WORKFLOW_ID` containing this workflow's UUID. Do not add publisher credentials, including through shared environment-variable groups. There is no TestFlight action.
- Require the native performance status where appropriate. Because measurements run on exact input branches, their status is attached to the source SHA; confirm the actual status/check context in GitHub before adding branch-protection requirements.

**Benchmark history**

- One native iOS **Build** action using aggregate scheme `WhimBenchmarkHistory`. It has no app/PR-code build dependency; collection runs in the pre-build hook. No TestFlight action.
- Schedule on **main**, initially hourly, plus main Branch Changes and trusted manual main runs. Exclude `benchmarks/results/**` and `benchmarks/README.md` from change-based starts. No PR, tag, `benchmark-input/`, or `benchmark-queue/` starts. Restrict manual branch selection to main. Runtime branch checks supplement these settings; they cannot stop Cloud injecting secrets into an incorrectly configured candidate workflow.
- Add the following environment variables **only to this workflow**:

| Variable | Value | Secret |
| --- | --- | --- |
| `WHIM_BENCHMARK_HISTORY_WORKFLOW_ID` | History workflow UUID | No |
| `WHIM_BENCHMARK_WORKFLOW_ID` | Benchmark workflow UUID | No |
| `WHIM_BENCHMARK_REPOSITORY` | `kumibrr/whim` | No |
| `WHIM_BENCHMARK_PRODUCT_ID` | Whim Cloud product UUID (`b675c35b-56c1-482b-b43d-ac966e431519`) | No |
| `WHIM_BENCHMARK_ROLLOUT_SHA` | Full main source SHA containing this implementation | No |
| `WHIM_BENCHMARK_GITHUB_TOKEN` | Repository-scoped credential: contents read/write and PR metadata read | Yes |
| `WHIM_ASC_ISSUER_ID` | App Store Connect API issuer | Yes |
| `WHIM_ASC_KEY_ID` | API key ID | Yes |
| `WHIM_ASC_PRIVATE_KEY` | ES256 `.p8` private key, actual newlines or literal `\n` | Yes |

The ASC key must read this product's Cloud workflows, runs, original PR metadata, actions and artifacts and start a rebuild when a provisional PR needs comparison. Signed artifact downloads receive neither API credential. The Git credential must create/delete execution/queue refs and append to main under the repository's rules. If protection rejects publication, fix the bot's authorized rule configuration; do not disable protection or force push. A PR-based publication mode is not implemented.

Keep existing Default and Release workflows, including release-preparation Actions. Their branch start conditions must exclude both `benchmark-input/` and `benchmark-queue/`; the Default PR condition remains targeting main. Configure generated-history file exclusions on ordinary main changes. Release builds always retain their full gates.

Changing the protocol or fixture intentionally starts a new series: review policy/runner changes together and advance the rollout SHA to that implementation. Merely publishing results or updating thresholds must not rewrite an earlier run's frozen decision.

## Local verification and recovery

```sh
npm ci
# Select an available dedicated iPhone simulator first.
export WHIM_IPHONE_SIMULATOR_UDID=<simulator-udid>
npm run test:performance
```

The runner prints the `.xcresult` path, then extracts and validates the same JSON attachment used by Cloud. Local observations are labeled `local` and are not published as main baselines. Optional `WHIM_DERIVED_DATA_PATH` moves products/results; `WHIM_XCODE_PACKAGE_CACHE_PATH` selects an Xcode package cache. Run functional `npm run test:all` separately so competing suites do not distort timing.

For a failed collector, rerun **Benchmark history on main**; completed native runs are re-read, not measured again or reevaluated against moving policy. For a new measurement attempt, use Cloud's rebuild control on the existing input run (new Cloud build identity). If its input was already closed/deleted, recreate the exact input ref at its encoded SHA with the authorized Git credential and start the Benchmark workflow manually; never move an existing ref. The collector permanently retains every distinct run it discovers. The collector retains a recreated ref while only its old published run is visible. A crash after publication but before deletion can also leave a completed input ref behind; it does not block the next terminally covered source. Rebuild it or prune it manually only after checking that no newer run is pending.

For a PR that reports no compatible baseline, seed/rebuild the eligible main source using the configured destination/toolchain, then run the collector. It retains the original provisional record and requests a new PR run once that compatible main evidence exists. Host changes can start a new environment series even with the same simulator model.

## Rollout acceptance

Before claiming live all-commit coverage:

- Run history manually on main and verify the first exact-source input Test run and its permanent main record/index. Confirm that only the publisher receives credentials.
- Push several source commits together, update/force-push/close a PR while its queue is pending, and confirm each observed retrievable source has a recorded terminal outcome or a visible pending input.
- Exercise a controlled slowdown, an unstable run, a failed build and an unavailable artifact. Confirm failures retain data, never seed a baseline, and retries remain immutable after policy/history advances.
- Publish during another main update and during release preparation; verify both data and release provenance survive. Verify a generated-only append queues no new benchmark and reruns no Default custom suite.
- Confirm scheduled collection and manual replay before native artifact expiry, and alert on repeated collection failures.

Physical acceptance remains pending: on a real iPhone record device/OS/source, measure Record-to-audible microphone capture and Stop-to-durable Note with usable audio, and verify normal/low-storage/interruption behavior. The closest automated coverage is the native UI benchmark plus `RecordingService`, `PCMRecorderHardware`, and fixture/store integration suites. See [paired-device acceptance](../e2e/physical/paired-device.e2e.test.md).
