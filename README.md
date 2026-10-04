<p align="center">
  <img src="assets/whim-icon.png" alt="Whim app icon" width="128" height="128">
</p>

<h1 align="center">Whim</h1>

<p align="center">
  Record voice Notes on iPhone and Apple Watch.<br>
  Send them to a webhook you control.
</p>

<p align="center">
  <a href="docs/receive-audio.md">Set up your receiver</a> ·
  <a href="docs/webhook-contract-v1.md">Webhook contract</a> ·
  <a href="#development">Development</a> ·
  <a href="docs/privacy.md">Privacy</a>
</p>

Whim saves your recordings on your devices and sends the audio and metadata directly to your chosen server. It has no accounts, hosted audio storage, analytics, or telemetry. Both apps use SwiftUI. The iPhone app requires iOS 18 or later, and the Watch app requires watchOS 11 or later.

## How it works

1. Start recording on your iPhone or Apple Watch. You can also start with Siri, App Shortcuts, the iPhone Lock Screen control, or a supported Action button.
2. Tap Stop to save a Note. Whim keeps the audio locally and starts delivery when you have a webhook configured and a connection.
3. Your webhook receives an `.m4a` recording and JSON metadata. Use your server to store or process them. The included receiver verifies signed requests and saves each Note once, even when both devices send it.

You can record offline or skip webhook setup. Unsent Notes stay on your device. History shows delivery status and lets you play a Note, inspect a failure, or retry delivery.

When enabled and available, on-device speech recognition generates short titles. Whim does not store full transcripts or use a server to generate titles. Apple Watch records independently and transfers Notes to your paired iPhone.

You choose how long to keep audio after successful delivery. The default is 30 days, and unsent Notes do not expire. Recordings can last up to five minutes.

## Receive your audio

Follow the [audio receiver setup guide](docs/receive-audio.md) to run the included receiver, connect Whim, and retrieve your recordings. Choose a local Wi-Fi setup or a persistent Linux service with HTTPS, authentication, and backups.

The receiver requires Node 24 or newer. You do not need Xcode or Apple development tools to run it. To build your own receiver, follow the [webhook contract](docs/webhook-contract-v1.md).

## Development

Install Xcode with iOS 18+ and watchOS 11+ support, Node 24 or newer, and Maestro for iPhone end-to-end tests.

`WhimCore` owns recording, persistence, delivery, recovery, and device synchronization. The iPhone and Watch apps call it through native presentation models.

Open `ios/Whim.xcworkspace` and run the `Whim` or `WhimWatch` scheme. Xcode resolves Swift Package Manager dependencies. Set your signing team for physical devices and preserve the checked-in bundle IDs and app-group entitlements.

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

`test:all` selects and boots compatible simulators when their IDs are not already supplied. Unit tests need no simulator. Integration tests exercise core and presentation services and the Watch model. E2E runs native iPhone Maestro journeys and Watch XCTest journeys against isolated webhook fixtures. These journeys clear test-app data. Run them on the dedicated CI simulators.

For focused presentation checks, run `swift test` from the repository root. WhimCore tests run with `swift test --package-path packages/WhimCore`. Each package uses explicit source membership with adjacent companion tests. The Node colocation checker validates membership and prevents tests from shipping in production targets.

Run `npm run test:integration:webhook` to test the reference receiver independently on macOS or Linux. These tests also run in the root integration suite and CI.

When native view files change, run `ruby scripts/configure-xcode-project.rb` and commit the updated Xcode project. The script requires the `xcodeproj` gem. Presentation model and test membership lives in the root `Package.swift`. Shared native behavior and test membership lives in `packages/WhimCore/Package.swift`.

`npm run test-server` starts the development webhook inbox on port 8787. Its page documents URLs and signed request details.

## Project guide

| Document | What it covers |
| --- | --- |
| [Domain model](CONTEXT.md) | The terms used in code and documentation. |
| [v1 design](docs/superpowers/specs/2026-09-04-whim-v1-design.md) | App behavior, architecture, and test interfaces. |
| [Startup flow](docs/startup-flow.md) | iPhone and Watch launch timelines. |
| [Migration verification](docs/swiftui-migration-verification.md) | SwiftUI migration checks and evidence. |
| [Physical acceptance](e2e/physical/paired-device.e2e.test.md) | Checks that require a real iPhone and Apple Watch. |

## Releasing

<details>
<summary>Versioning and changelogs</summary>

[Changesets](https://github.com/changesets/changesets) owns the App Store marketing version in `ios/package.json`, under `@whim/app`. Record user-visible changes with `npm run changeset`. At release time, run `npm run release:version` to bump the version, write `ios/CHANGELOG.md`, and sync `MARKETING_VERSION` into every Xcode target. Never edit `MARKETING_VERSION` by hand. Version 1.0.0 is the initial release and has no changelog. Xcode's distribution flow manages build numbers.

</details>

<details>
<summary>Release checks and App Store submission</summary>

The [webhook contract](docs/webhook-contract-v1.md) documents signing and persistent Note-ID deduplication. The [privacy policy](docs/privacy.md) describes local processing, paired-device transfer, and user-selected endpoints. The [paired-device matrix](e2e/physical/paired-device.e2e.test.md) records the physical checks still required before release; its [test guide](e2e/physical/paired-device-test-guide.md) explains how to run and report every case.

Run `npm run verify:release` on macOS to create a clean unsigned Release device archive. The command validates all four embedded executables, privacy manifests, and submission metadata. It checks the shared marketing version and build number, lowercase `whim` display names, and the export-compliance key. CI runs this after `test:all`. The archive defaults to `ios/build/Whim.xcarchive`. Override it with `WHIM_ARCHIVE_PATH`. Distribution signing and physical acceptance remain separate release requirements.

Run `./scripts/check-release-privacy.sh` to check SDK references and source manifest reasons. Pass a built `whim.app` path to also inspect every embedded target's manifest. After building or archiving Release, run `./scripts/check-release-fixtures.sh /absolute/path/to/whim.app` to inspect all four executables for debug injection code. That check also requires the product-owner-approved, non-sensitive recording at `src/iphone/webhook-configuration/configuration-test.m4a`, matching the runtime configuration-test asset. The development fixture is not release approval.

Require both `tooling` and `apple` CI jobs in repository branch protection. The [approved configuration-test recording](docs/configuration-test-asset.md) is included. Physical sign-off, signing/provisioning, and App Store disclosure review remain prerequisites for publishing.

Publish the privacy policy at a public URL and link to it from App Store Connect and an accessible place inside the app, as required by [App Review guideline 5.1.1](https://developer.apple.com/app-store/review/guidelines/#data-collection-and-storage). Review [App Privacy answers](https://developer.apple.com/app-store/app-privacy-details/) against the actual release and endpoint arrangement. The manifest declares no tracking or app-operator collection; that declaration does not establish a user-selected webhook's collection practices. The release privacy gate checks required-reason API declarations and their presence in embedded targets.

</details>
