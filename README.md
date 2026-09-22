# Whim

Whim captures voice Notes on iPhone and Apple Watch, keeps them recoverable locally, and delivers them to a user-controlled webhook. Both apps use SwiftUI; WhimCore owns native recording, persistence, delivery, recovery and device synchronization.

## Development

Requires a complete Xcode installation supporting iOS 18+ and watchOS 11+, Node for repository scripts and the webhook receiver, and Maestro for iPhone end-to-end tests. No CocoaPods, Expo, React Native or Metro setup is needed.

The reference webhook requires Node 24 or newer. Run `npm run test:integration:webhook` independently on macOS or Linux. Its tests also run in the root integration suite and CI.

Open `ios/Whim.xcworkspace` and run the **Whim** or **WhimWatch** scheme. Xcode resolves Swift Package Manager dependencies automatically. Set your signing team for physical devices; preserve the checked-in bundle IDs and app-group entitlements.

```sh
npm ci
npm run ios
```

`npm run ios` builds, installs and launches the native iPhone simulator app. It preserves an existing installation's data. To select a simulator, set `WHIM_IPHONE_SIMULATOR_UDID`.

## Tests

```sh
npm run test:unit
eval "$(./scripts/boot-apple-simulators.sh)"
npm run test:integration
npm run test:e2e
npm run test:all
```

`test:all` selects and boots compatible simulators when their IDs are not already supplied. Unit tests need no simulator. Integration tests exercise core/presentation services and the Watch model. E2E runs native iPhone Maestro journeys and Watch XCTest journeys against isolated webhook fixtures. These journeys clear test-app data; use the dedicated CI simulators, not devices holding personal Notes.

For focused presentation checks, run `swift test` from the repository root. WhimCore tests run with `swift test --package-path packages/WhimCore`. Each package uses explicit source membership with adjacent companion tests. The Node colocation checker validates membership and prevents tests from shipping in production targets.

When native view files change, run `ruby scripts/configure-xcode-project.rb` (requires the `xcodeproj` gem) and commit the updated Xcode project. Presentation model/test membership lives in the root `Package.swift`; shared native behavior/test membership lives in `packages/WhimCore/Package.swift`.

`npm run test-server` starts the development webhook inbox on port 8787. Its page documents URLs and signed request details.

See [CONTEXT.md](CONTEXT.md), the [v1 design](docs/superpowers/specs/2026-09-04-whim-v1-design.md), the [iPhone and Watch startup timelines](docs/startup-flow.md), and [migration verification](docs/swiftui-migration-verification.md). Real hardware acceptance procedures live under `e2e/physical/`.

## Release gates

The [webhook contract](docs/webhook-contract-v1.md) documents signing and persistent Note-ID deduplication. [Privacy](docs/privacy-v1.md) describes local processing, paired-device transfer, and user-selected endpoints. The [paired-device matrix](e2e/physical/paired-device.e2e.test.md) records the physical checks still required before release.

Run `./scripts/check-release-privacy.sh` to check SDK references and manifest reasons. After building or archiving Release, run `./scripts/check-release-fixtures.sh /absolute/path/to/whim.app` to inspect all four executables for debug injection code. That gate also requires the product-owner-approved, non-sensitive recording at `src/iphone/webhook-configuration/configuration-test.m4a`, matching the runtime configuration-test asset. The development fixture is not release approval.

Require both `tooling` and `apple` CI jobs in repository branch protection. The [approved configuration-test recording](docs/configuration-test-asset.md) is included. Physical sign-off, signing/provisioning, and App Store disclosure review remain prerequisites for publishing.
