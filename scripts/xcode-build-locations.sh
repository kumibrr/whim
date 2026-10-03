#!/usr/bin/env bash
# Keep Build/ inside the script-owned DerivedData even when Xcode uses a Custom build location.
# Set WHIM_DERIVED_DATA_PATH to move everything, for example to an external volume.

whim_derived_data="${WHIM_DERIVED_DATA_PATH:-$whim_root/ios/build/DerivedData}"
whim_build_products="$whim_derived_data/Build/Products"
whim_xcode_build_locations=(
  -derivedDataPath "$whim_derived_data"
  SYMROOT="$whim_build_products"
  OBJROOT="$whim_derived_data/Build/Intermediates.noindex"
)
