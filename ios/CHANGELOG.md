# @whim/app

## 1.2.1

### Patch Changes

- 43cc254: - Improve Apple Watch synchronization recovery and prevent duplicate peer transfers.
  - Explain Watch availability and Note audio synchronization failures more clearly.
  - Refine the Corner complication layout and artwork.
  - Preserve the “Note saved” confirmation when recording events arrive after Stop completes.
  - Add automated performance regression benchmarks, permanent history, and performance summaries in GitHub releases.

## 1.2.0

### Minor Changes

- 6aa4460: On iPhone, invoke Record a Whim again to stop and send the active recording from the Action button, Siri, or Lock Screen control.
- 779daa2: Show existing users a one-time update sheet using the onboarding layout. Fresh installs skip announcements for their installed release. Release content supports setup guides, information, and optional settings controls without changing saved defaults until Continue.
- 5606e3c: Automatically stop, save, and send Apple Watch recordings after speech followed by silence. Auto-stop is enabled by default with a 3-second delay. Adjust the delay from 2 to 10 seconds or disable it in Settings → Apple Watch; the Watch keeps its last synchronized choice while offline. Existing users see a one-time update screen with the suggested settings and can adjust them or skip setup.

### Patch Changes

- aa76f79: Preserve iPhone Debug App Intents metadata so Live Activity Stop runs in the recorder's app process. Validate built system surfaces before E2E and handle both Live Activity permission prompts. Avoid a simulator startup race when another client boots the device after shutdown.
- aa76f79: Temporarily hide Lock Screen and Control Center setup guidance, finishing onboarding after microphone setup on iPhones without an Action button.
  
  Group shortcut guidance under Shortcuts in Settings, showing Configure action button only on supported iPhones. Keep Control Center, Lock Screen, and Apple Watch complication guidance hidden for now.
- 7cb5ef3: Fit the Dynamic Island Stop circle within its expanded layout, refine the waveform stroke, and show the same voice-reactive controls on the Lock Screen.
- c0a42cf: Keep the full Watch capture control available to touch and accessibility, and adapt Previous Notes spacing to the system toolbar height.

## 1.1.2

### Patch Changes

- c68467a: Recover from a Watch recording whose transfer to iPhone was interrupted. A truncated copy no longer blocks device synchronization and delivery of all other Notes, and a resend from the Watch replaces it.
- d6e91a4: Keep the Retry sync icon and text together inside one compact Liquid Glass button.
- d502f49: Show Watch Notes on iPhone while their audio is synchronizing. Corrupt audio is retried for up to three total transfers per cycle, then offers Retry sync and Delete without blocking other Notes or changing a successful Delivery.

  Note details show a compact Retry sync control and retain a row for every audio resend, including its outcome and request time.

## 1.1.1

### Patch Changes

- fc417ad: Use a neutral Continue button before requesting microphone permission on iPhone and Apple Watch. Remove the iPhone skip and back actions before the system prompt while allowing users to finish onboarding after denying access.

## 1.1.0

### Minor Changes

- Add guided onboarding for microphone permission, quick recording access, and webhook setup. Save webhook changes automatically and preserve the webhook URL and onboarding progress between launches.
