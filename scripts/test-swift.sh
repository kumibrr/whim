#!/usr/bin/env bash
set -euo pipefail

whim_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$whim_root/scripts/apple-toolchain.sh"
whim_derived_data="${WHIM_DERIVED_DATA_PATH:-$whim_root/ios/build/DerivedData}"

case "${1:-}" in
  unit)
    swift test --package-path "$whim_root/packages/WhimCore" --filter WhimCoreUnitTests
    swift test --package-path "$whim_root" --filter WhimIPhoneUnitTests
    ;;
  integration)
    swift test --package-path "$whim_root/packages/WhimCore" --filter WhimCoreIntegrationTests
    swift test --package-path "$whim_root" --filter WhimIPhoneIntegrationTests
    : "${WHIM_IPHONE_SIMULATOR_UDID:?Run: eval \"$(./scripts/boot-apple-simulators.sh)\"}"
    # Package schemes expose their test action when opened from the package directory.
    # Exercise the actual iOS audio session; macOS excludes this platform boundary.
    (
      cd "$whim_root/packages/WhimCore"
      xcodebuild test -quiet \
        -scheme WhimCore \
        -derivedDataPath "$whim_derived_data" \
        -only-testing:WhimCoreIntegrationTests/AVAudioRecorderSessionIntegrationTests \
        -only-testing:WhimCoreIntegrationTests/PCMRecorderHardwareIntegrationTests \
        -destination "id=${WHIM_IPHONE_SIMULATOR_UDID}" \
        CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=-
    )
    : "${WHIM_WATCH_SIMULATOR_UDID:?Run: eval \"$(./scripts/boot-apple-simulators.sh)\"}"
    xcodebuild test -quiet \
      -workspace "$whim_root/ios/Whim.xcworkspace" \
      -scheme WhimWatch \
      -derivedDataPath "$whim_derived_data" \
      -only-testing:WhimWatchTests \
      -destination "id=${WHIM_WATCH_SIMULATOR_UDID}" \
      CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=-
    ;;
  *)
    echo "Usage: $0 unit|integration" >&2
    exit 64
    ;;
esac
