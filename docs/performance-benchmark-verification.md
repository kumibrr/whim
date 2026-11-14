# Performance benchmark implementation verification

Implementation: `d7d14d2`, following the [approved design](superpowers/specs/2026-11-13-performance-benchmarks-design.md). See [workflow setup and acceptance](performance-benchmarks.md) before enabling hosted execution. No Cloud workflow, secret, main push, release or permanent benchmark result was created during local implementation.

## Evidence

- Node/tooling: 141 tests pass, including policy conformance, real Git append/conflict/concurrent publication, frozen-policy replay, release compatibility, role isolation, actual attachment naming, 100+ queue refs, same-SHA main/PR coverage gaps, recreated-input races, superseded/closed PR heads, rollout filtering and safe generated destinations.
- Shared native comparator: Swift XCTest policy/conformance tests pass.
- Fixture: integration tests use real SQLite/audio storage and verify exactly 1,000 deterministic Notes, isolated preferences, idempotent setup and invalid-input rejection.
- Native installed app: the final optimized run on `d7d14d2` passed XCTest (1/1, no skips, no runtime warnings), completing all five metrics with two warmups and ten samples each. Its actual XCResult attachment independently passed the collector's validation as a local baseline. Median milliseconds: launch.empty 4608.09, launch.populated 4527.54, record.populated 1387.30, stop.populated 2461.89, timeline.populated 2626.31. MAD remained below 1.5% for every metric. The XCResult and exported JSON are retained under ignored `ios/build/Final-Performance*`; these diagnostics were not published as permanent history.
- Controlled local launch experiment: an added two-second delay produced two batch medians of 6906.78 / 6726.60 ms against a measured 4741.75 ms baseline. Native XCTest failed with the confirmed-regression assertion. The intentionally partial failure attachment was extracted and verified as an error, preserving its samples. The experimental source changes were removed.
- Unsigned Release archive: fixture exclusion, privacy and metadata checks pass on the actual app, embedded Watch app and extensions.
- Full `test:all`: Node/Swift and focused native integration checks pass, but repeated complete runs stalled during native iPhone test-host startup. No application assertion failure was reported by those stalled runs. All 27 iPhone E2E journeys passed across the completed run and focused retries; the Shortcuts sheet needed one retry. All 20 Watch E2E tests passed with no skips. The separate final normal benchmark passed; this does not make the stalled full entrypoint green.

The local Mac uses Xcode 27.1, macOS 27.2.1 and iOS/watchOS 27 simulators. A corrupt shared SwiftPM cache required a valid worktree-local package cache; local compiler concurrency was capped at two. The Mac initially ran out of disk space under heavy swap usage, then recovered after shutting down the extra benchmark simulator. A later user-authorized cleanup recovered about 10.7 GiB of actual disk space (4.9 to 15.5 GiB available): stale November 10 review build directories, compiler caches, a cached browser update and system logs from shut-down simulators. Source files, simulator app data, benchmark products and test results were retained. Stale iPhone and Watch test-manager sessions required restarting the dedicated CI simulators before native actions. Local archive build-location overrides were removed after Xcode reported a missing BuildProductsPath; the standard archive layout then passed. These infrastructure failures were not counted as successful tests.

## Review and decisions

One fresh reviewer inspected the whole implementation. All five Important findings and the rollout-boundary finding were reproduced and fixed in one pass. No review findings were deferred. Live hosted configuration/transport, physical acceptance and independent duplicate native runs were outside that review; local verification remains the implementer's responsibility.

Implementation decisions retained from the execution ledger:

- Proceed inline under the user's approval, without another plan-approval round. Risk: an unexpressed preference would require a later adjustment.
- Keep native comparison support in a dependency-free test-only Swift package. Risk: Node and Swift implementations could drift; shared conformance vectors test their agreement.
- Preserve observed PR backlog with temporary source refs under `benchmark-queue/`. Risk/cost: extra refs and Git API operations; permanent measurement data stays on main.
- Share attachment verification between local tests and Cloud collection, and commit their dependent implementation together. Risk: broader source slices; module companions retain separate behavior coverage.
- Use local cache/concurrency workarounds rather than changing dependency versions. Risk: local build scheduling differs from Cloud, while app/test behavior and package constraints remain unchanged.
- Review the committed implementation while broad verification continues. Risk: later changes need explicit coverage; all consequential fixes received reproducing tests and verification.
- Keep live Cloud configuration, credentials, rules and hosted artifact transport as explicit rollout acceptance. Risk: hosted misconfiguration remains possible until that acceptance runs.
- Keep physical microphone latency, interruptions and real-device sign-off pending. Risk: these hardware behaviors remain outside the simulator gate.
