# @whim/app

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
