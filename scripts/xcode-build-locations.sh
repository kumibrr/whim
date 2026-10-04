#!/usr/bin/env bash
# Keep Build/ inside the script-owned DerivedData even when Xcode uses a Custom build location.
# Set WHIM_DERIVED_DATA_PATH to move everything, for example to an external volume.

whim_build_locations_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
whim_derived_data="${WHIM_DERIVED_DATA_PATH:-$whim_build_locations_root/ios/build/DerivedData}"
whim_build_products="$whim_derived_data/Build/Products"
whim_xcode_build_locations=(
  -derivedDataPath "$whim_derived_data"
  SYMROOT="$whim_build_products"
  OBJROOT="$whim_derived_data/Build/Intermediates.noindex"
)
# Sourced helper. Sets whim_build_products and whim_build_intermediates for the Whim scheme.
whim_resolve_build_locations() {
  local whim_locations
  whim_locations="$(xcodebuild -showBuildSettings -json \
    -workspace "$whim_build_locations_root/ios/Whim.xcworkspace" -scheme Whim -configuration Debug \
    -derivedDataPath "$1" -destination "$2" \
    SYMROOT="$1/Build/Products" OBJROOT="$1/Build/Intermediates.noindex" \
    | node "$whim_build_locations_root/scripts/xcode-build-locations.mjs")"
  whim_build_products="${whim_locations%%$'\n'*}"
  whim_build_intermediates="${whim_locations#*$'\n'}"
}
