#!/usr/bin/env bash
set -euo pipefail
whim_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$whim_root/scripts/apple-toolchain.sh"
source "$whim_root/scripts/xcode-build-locations.sh"
if [[ -z "${WHIM_IPHONE_SIMULATOR_UDID:-}" ]]; then
  eval "$("$whim_root/scripts/boot-apple-simulators.sh")"
fi
xcodebuild build -quiet -workspace "$whim_root/ios/Whim.xcworkspace" -scheme Whim "${whim_xcode_build_locations[@]}" -destination "id=$WHIM_IPHONE_SIMULATOR_UDID" CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=-
whim_resolve_build_locations "$whim_derived_data" "id=$WHIM_IPHONE_SIMULATOR_UDID"
xcrun simctl install "$WHIM_IPHONE_SIMULATOR_UDID" "$whim_build_products/Debug-iphonesimulator/whim.app"
xcrun simctl launch "$WHIM_IPHONE_SIMULATOR_UDID" app.whim.ios
open -a Simulator
