#!/usr/bin/env bash
set -euo pipefail
whim_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$whim_root/scripts/apple-toolchain.sh"
if [[ -z "${WHIM_IPHONE_SIMULATOR_UDID:-}" ]]; then
  eval "$("$whim_root/scripts/boot-apple-simulators.sh")"
fi
source "$whim_root/scripts/xcode-build-locations.sh"
xcodebuild build -quiet -workspace "$whim_root/ios/Whim.xcworkspace" -scheme Whim "${whim_xcode_build_locations[@]}" -destination "id=$WHIM_IPHONE_SIMULATOR_UDID" CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=-
xcrun simctl install "$WHIM_IPHONE_SIMULATOR_UDID" "$whim_build_products/Debug-iphonesimulator/whim.app"
xcrun simctl launch "$WHIM_IPHONE_SIMULATOR_UDID" app.whim.ios
open -a Simulator
