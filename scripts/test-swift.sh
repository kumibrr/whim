#!/usr/bin/env bash
set -euo pipefail

whim_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$whim_root/scripts/apple-toolchain.sh"
whim_derived_data="${WHIM_DERIVED_DATA_PATH:-$whim_root/ios/build/DerivedData}"

case "${1:-}" in
  unit)
    swift test --package-path "$whim_root/packages/WhimCore" --filter WhimCoreUnitTests
    : "${WHIM_WATCH_SIMULATOR_UDID:?Run: eval \"$(./scripts/boot-apple-simulators.sh)\"}"
    xcodebuild test -quiet \
      -workspace "$whim_root/ios/Whim.xcworkspace" \
      -scheme WhimWatch \
      -derivedDataPath "$whim_derived_data" \
      -only-testing:WhimWatchTests \
      -destination "id=${WHIM_WATCH_SIMULATOR_UDID}" \
      CODE_SIGNING_ALLOWED=NO
    ;;
  integration)
    swift test --package-path "$whim_root/packages/WhimCore" --filter WhimCoreIntegrationTests
    : "${WHIM_IPHONE_SIMULATOR_UDID:?Run: eval \"$(./scripts/boot-apple-simulators.sh)\"}"
    xcodebuild test -quiet \
      -workspace "$whim_root/ios/Whim.xcworkspace" \
      -scheme Whim \
      -derivedDataPath "$whim_derived_data" \
      -only-testing:WhimBridgeIntegrationTests \
      -destination "id=${WHIM_IPHONE_SIMULATOR_UDID}" \
      CODE_SIGNING_ALLOWED=NO
    ;;
  *)
    echo "Usage: $0 unit|integration" >&2
    exit 64
    ;;
esac
