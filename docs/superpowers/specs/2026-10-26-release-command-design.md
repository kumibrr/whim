# One-command app releases

## Intent and scope

Provide `npm run release` for the release procedure agreed in this conversation: consume Changesets, update the project version and changelog, validate, commit, push to main, and publish the version tag and GitHub Release. The existing Xcode Cloud Release workflow handles the signed archive and App Store Connect upload after the tag is pushed.

This is a small tooling change around existing commands. Implementing it must not release a new app version or create a tag. App Store submission and the documented physical acceptance checks remain manual.

## Approaches

- **Local release command — selected by the user.** Reuse the existing macOS test and archive commands, Changesets, Git, and GitHub CLI. This works with GitHub Actions disabled and makes the release an explicit local action.
- **GitHub Actions release PR.** Centralizes release preparation but requires enabling Actions, configuring permissions, and retaining a separate merge/publication step. Deferred.

## Command behavior

1. Require macOS, the existing Apple tooling, installed npm dependencies, authenticated GitHub CLI access, a clean checkout, and pending app Changesets. Fetch origin and require the current commit to equal `origin/main`. A clean release branch at that commit is allowed, so managed worktrees can release without checking out main elsewhere.
2. Run Changesets versioning, synchronize every Xcode `MARKETING_VERSION` from `ios/package.json`, and update the npm lockfile without running install scripts. Also update the existing `release:version` command so standalone version preparation keeps the lockfile consistent.
3. Require a new stable app version and an unused `vX.Y.Z` tag. Extract that version's release notes from the generated app changelog. Keep Xcode Cloud responsible for distribution build numbers.
4. Run `npm run test:all` and `npm run verify:release`. Both must succeed before creating a release commit or pushing anything.
5. Confirm only the expected Changesets, app manifest/changelog, lockfile, and Xcode project files changed. Commit those files as `chore(ios): release X.Y.Z`, create the version tag, and atomically push the release commit to `origin/main` together with the tag. Use a normal fast-forward push; never force-push. The current checkout's branch advances, while other local checkouts are left alone.
6. Create a GitHub Release for the already-pushed tag, using the generated changelog section. Print the release URL and the Xcode Cloud workflow URL. Report that the cloud build was triggered; do not claim that upload or processing has completed.

## Failure and recovery

Stop on the first failure. Before publication, preserve generated files and any local release commit/tag for inspection; do not reset, delete, or discard work automatically. Explain the failed stage and concrete recovery commands. If GitHub Release creation fails after the atomic push, explain that the tag already triggered Xcode Cloud and provide a publication-only recovery command instead of running versioning again. Reject unexpected concurrent edits rather than committing them.

## Validation

Use companion Node tests for the release command's public interface, with external process boundaries controlled in fixtures. Exercise successful preparation/publication, missing Changesets and preflight failures, failed validation preventing publication, unexpected edits, rejected pushes, changelog notes, and recovery after GitHub publication failure. Use the real version synchronization and metadata checks where practical. Run the affected tooling suite during development and `npm run test:all` before declaring completion. Verify release preparation in an isolated fixture without pushing a real tag.

## Builder choices

Use Node ESM and the repository's existing test runner; add no dependency. Keep process orchestration small and stop rather than attempting automatic rollback. Update the README with prerequisites, the full procedure, failure recovery, and the existing Xcode Cloud tag/upload handoff.
