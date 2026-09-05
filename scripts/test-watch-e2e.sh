#!/usr/bin/env bash
set -euo pipefail

: "${WHIM_WATCH_SIMULATOR_UDID:?Run: eval \"$(./scripts/boot-apple-simulators.sh)\"}"

whim_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$whim_root/scripts/apple-toolchain.sh"
whim_derived_data="${WHIM_DERIVED_DATA_PATH:-$whim_root/ios/build/DerivedData}"

xcodebuild test -quiet \
  -workspace "$whim_root/ios/Whim.xcworkspace" \
  -scheme WhimWatchUITests \
  -derivedDataPath "$whim_derived_data" \
  -only-testing:WhimWatchUITests \
  -destination "id=${WHIM_WATCH_SIMULATOR_UDID}" \
  CODE_SIGNING_ALLOWED=NO
