# CI and published releases in Xcode Cloud

GitHub Actions performs Changesets/npm preparation only. Xcode Cloud owns tooling tests, webhook integration, Swift unit/integration tests, iPhone Maestro journeys, Watch UI tests, product builds and release archive validation. `npm run release` is a read-only pointer to GitHub publishing; it does not run local CI or mutate Git.

## Publishing

1. Commit pending `@whim/app` Changesets with source changes and merge them to main.
2. Publish a GitHub Release with a **new stable tag** at current main. Use the next Changesets version, either `1.2.3` or `v1.2.3`. A raw stable tag push is also supported; duplicate tag/release events reuse the same preparation. Draft releases do not start preparation. Existing tags are never moved.
3. Actions prepares the tagged source in an isolated temporary checkout using the trusted version tooling from main. It consumes Changesets and updates the app manifest, changelog, npm lockfile and every Xcode target's marketing version. `.release/prepared.json` records the original tag, tag object, tagged commit and resulting version. `release-preparation/<tag>` retains the generated commit, whose parent is the original source commit.
4. Actions tries an **atomic push** of that commit to both `main` and `release-build/<tag>`. If main rejects the push, it opens a preparation PR targeting main. Merge that PR without adding source edits. No release branch is published while the PR is pending. A main push resumes the handoff after the actual merged tree matches the prepared tree, including squash/rebase merges.
5. Only the `release-build/` branch starts the Cloud Release workflow. The cloud checkout gate verifies the unchanged original tag, the preparation provenance, the cloud branch commit, and the matching current main tree again before tests/builds. The archive action runs `test:all` before its native archive, then checks fixture exclusion, privacy manifests and submission metadata on the actual embedded app, Watch app and extensions.
6. Wait for Cloud and App Store Connect processing; then select the build for submission. Existing Internal TestFlight distribution is retained. App Store submission and physical acceptance remain manual.

No release/tag was created to test this migration. Existing release `1.1.3` is not a migration test target.

## Main advancement, protection and recovery

Main must equal the tagged commit when preparation starts. If main advances during preparation, nothing is handed to Cloud. If unrelated source lands while a preparation PR waits, the merged main tree differs and the handoff fails. This deliberately requires a new release tag from reconciled main; it never silently includes untagged source, releases stale source, or drops main changes. An empty commit or a merge strategy that preserves exactly the prepared tree is acceptable during finalization. Once a release branch exists, it is immutable through this tooling; ordinary main advancement does not prepare another release. A delayed/retried Cloud build refuses a now-different main tree.

Check the Actions log, both remote release branches and main before recovering a failed push: a lost response may hide success. Re-run **Prepare Cloud release** with the same existing tag using `workflow_dispatch`. It reuses committed preparation, never consumes Changesets twice and never overwrites an existing differing branch. A blank dispatch resumes the provenance currently on main. Do not delete/change provenance, force-push preparation/build branches, move tags, or manually run versioning for a partially prepared release.

All release events share one Actions concurrency group with cancellation disabled. GitHub retains one running and one pending run; bursts of releases can supersede a pending event. Dispatch the omitted tag explicitly; stale competing releases fail the main gate. Publish releases sequentially. No version PR is created by an ordinary main push.

Allow Actions to create pull requests in repository **Settings → Actions → General**. The workflow requests only contents-write and pull-requests-write. The repository's `GITHUB_TOKEN` performs the Git handoff; Xcode Cloud's GitHub integration consumes external repository webhooks, rather than another GitHub Actions workflow. GitHub does suppress recursive Actions runs from this token, so the successful direct atomic push completes its own handoff in the same run. If a preparation PR is merged by automation using `GITHUB_TOKEN`, dispatch the blank resume explicitly because that push will not start a new Actions run. If an organization disallows bot PRs, open a PR from the already pushed `release-preparation/<tag>` branch and merge it normally; do not bypass protection.

## Cloud workflow configuration

Primary repository: `https://github.com/kumibrr/whim.git`. Workspace: `ios/Whim.xcworkspace`. Use a current Xcode/macOS image with a compatible iOS 18+/watchOS 11+ simulator pair. `scripts/boot-apple-simulators.sh` chooses the newest matching installed generation and fails clearly if no compatible pair is available. A cloud image lacking Watch runtimes cannot provide the required coverage; provision/select an image with both runtimes rather than skipping tests.

**Release** ([workflow](https://appstoreconnect.apple.com/teams/3a7fa4a7-7fbd-40c9-b79c-659659e627f6/xcode-cloud/products/b675c35b-56c1-482b-b43d-ac966e431519/workflows/62dc6f87-fa57-4e9e-810a-43aa1dd13728)):

- Replace Tag Changes with Branch Changes matching branches **beginning with `release-build/`**. Remove every tag-based start condition. Do not point it at `release-preparation/` or original tags.
- Keep a single iOS Archive action, scheme `Whim`, App Store Connect distribution preparation, and the existing Internal TestFlight post-action. Whim embeds the Watch app and both extensions.
- Keep clean builds. No signing secrets are placed in Actions; Cloud manages signing/build numbers.

**PR CI**:

- Enable Pull Request Changes targeting main (all files, including drafts as supported). A single iOS Build action with scheme `Whim` suffices; no TestFlight post-action.
- The pre-build hook runs the same full suite and an unsigned clean release archive through `verify:release`. The native build is an additional product build. Never substitute a native test-only action that omits Maestro or Watch coverage.
- Replace old required GitHub `tooling`/`apple` statuses with the actual Cloud PR status after a successful representative Cloud PR run. Do not remove required coverage during cutover.

Hooks under `ios/ci_scripts` are discovered beside the Xcode workspace. Each hook establishes Node 24's PATH through Homebrew; pre-build also installs Java 17 and checksum-verified Maestro 2.10.0. Setup needs outbound access to npm, Homebrew and GitHub. No sudo is used. Dependencies and exports are established per action; no state is assumed to cross cloud machines. `ci_post_clone.sh` checks release provenance; `ci_pre_xcodebuild.sh` installs npm dependencies and runs the complete suite; `ci_post_xcodebuild.sh` fails on a failed native action and validates `CI_ARCHIVE_PATH` for archive actions. The supported workflow shapes are Build and Archive; other action kinds fail explicitly so coverage cannot disappear through a configuration change.

A pre-build failure blocks the native archive/distribution. Suite output is in the Cloud custom-script log. Xcode test result bundles are under `ios/build/DerivedData/Logs/Test`, webhook output is `ios/build/webhook-e2e.log`, and Maestro writes `~/.maestro/tests`. Cloud does not promise to retain arbitrary custom-script files as downloadable artifacts; inspect the logs and reproduce locally when those files are unavailable. Native cloud action artifacts remain managed by Cloud.

## Sources

- [Apple: custom build hooks](https://developer.apple.com/documentation/xcode/writing-custom-build-scripts)
- [Apple: Cloud environment variables and isolated actions](https://developer.apple.com/documentation/xcode/environment-variable-reference)
- [Apple: start conditions](https://developer.apple.com/documentation/xcode/configuring-start-conditions)
- [Apple: dependencies in Cloud](https://developer.apple.com/documentation/Xcode/Making-Dependencies-Available-to-Xcode-Cloud)
- [GitHub: release, push and dispatch events](https://docs.github.com/en/actions/reference/workflows-and-actions/events-that-trigger-workflows)
- [GitHub: recursive workflow suppression](https://docs.github.com/en/actions/how-tos/writing-workflows/choosing-when-your-workflow-runs/triggering-a-workflow)

## Applied settings and validation (2026-10-30)

The existing Release workflow's tag trigger was removed and its branch prefix is now `release-build/`. Its Whim archive, App Store Connect distribution preparation and Internal TestFlight post-action were retained. The existing Default workflow now starts on PR changes targeting main as well as main pushes; its single iOS Whim build runs the complete suite and embeds Watch products, avoiding duplicate full-suite runs on separate action machines. Repository Actions PR creation is enabled; default token permissions remain read, with write access scoped by the preparation workflow. Main currently has no protection/rulesets. Automatic deletion of merged PR branches is disabled: keep it disabled for preparation branches, which retain provenance required by retries and Cloud verification. If one is deleted, restore `release-preparation/<tag>` at the original preparation PR head commit and dispatch the tag again; do not regenerate version files or move tags.

Tooling regressions use real local bare Git remotes, actual Changesets/npm and mocked GitHub/Apple boundaries. They do not prove live Cloud webhook delivery, Git authentication, available simulator runtimes or Maestro execution on Apple's machines. A representative Cloud PR build is the cutover acceptance check. The migration does not create a real release/tag to exercise that path.

The first Cloud PR run reached the full suite: Node/Java/Maestro installation, dependency setup, source gates and all 70 initial tooling tests passed. It exposed a scheduler-dependent recording test assertion (an interruption task may start after Stop completes and validly return nil), now covered for both orderings. It also exposed incompatible simulator device selection: bootstrap now selects a device type listed in the runtime’s supported-device catalogue and within its declared version bounds and `test:all` propagates bootstrap failures immediately. Deterministic tooling regressions cover compatibility and failure propagation. The local unsigned release archive passed every embedded-bundle gate; local iPhone E2E and separate Watch UI validation were blocked by driver/paired-simulator connection timeouts. These do not waive Cloud E2E acceptance.

The second Cloud run failed closed at simulator creation before tests. Version bounds alone do not establish runtime support, so selection now also respects `supportedDeviceTypes` from the installed runtime catalogue. A regression exercises a nominally compatible but catalogue-excluded model through the real shell bootstrap. Bootstrap logs the chosen model/runtime IDs and identifies which creation command fails, so any remaining Cloud-specific limitation is visible. These changes await another Cloud run. The subsequent local full-suite retry reached unit and webhook integration success but exceeded its ten-minute limit on a Mac using about 21 GB of swap; it is not recorded as a full-suite pass.

The catalogue-aware Cloud run successfully booted iPhone Duo (iOS 27.1) and Watch Series 12 (watchOS 27.0), passed all 74 tooling tests and the recording tests, then exposed a second scheduler-dependent test. The delivery scheduler regression now waits for the sleeper's second request instead of assuming twenty task yields are enough; its retry interval and callback assertions remain intact. All 23 delivery-service tests pass locally. Complete Cloud integration/E2E acceptance remains outstanding.

Cloud now passes all 131 core unit tests and reaches integration tests. Its macOS Keychain adapter tests require an unlocked default keychain, which is not available in the headless action by default. The pre-build hook wraps validation in a disposable, empty-password keychain containing synthetic test credentials only. Existing signing keychains remain on the search list; the original default and search list are restored, and the temporary keychain is deleted before the native Cloud build. Setup/test/cleanup failures propagate and cleanup still runs. This does not change application credential storage or signing credentials. [Apple’s security tool implementation](https://github.com/apple-oss-distributions/Security/blob/main/SecurityTool/macOS/keychain_list.c) defines search-list/default restoration, including clearing an originally absent default.
