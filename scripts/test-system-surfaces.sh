#!/usr/bin/env bash
set -euo pipefail
whim_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$whim_root/scripts/apple-toolchain.sh"
if [[ -z "${WHIM_IPHONE_SIMULATOR_UDID:-}" ]]; then
  eval "$("$whim_root/scripts/boot-apple-simulators.sh")"
fi
whim_derived_data="${WHIM_DERIVED_DATA_PATH:-$whim_root/ios/build/DerivedData}"
xcodebuild test -quiet \
  -workspace "$whim_root/ios/Whim.xcworkspace" -scheme Whim \
  -derivedDataPath "$whim_derived_data" \
  -only-testing:WhimSystemSurfaceTests \
  -destination "id=${WHIM_IPHONE_SIMULATOR_UDID}" \
  CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=-
python3 "$whim_root/scripts/verify-system-surfaces.py" "$whim_derived_data"
