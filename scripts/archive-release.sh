#!/usr/bin/env bash
# Reproducible unsigned device archive. Distribution signing and physical acceptance are separate gates.
set -euo pipefail
whim_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$whim_root"
source "$whim_root/scripts/apple-toolchain.sh"
whim_archive="${WHIM_ARCHIVE_PATH:-$whim_root/ios/build/Whim.xcarchive}"
./scripts/check-release-privacy.sh
./scripts/check-release-metadata.sh
xcodebuild clean archive -quiet \
  -workspace ios/Whim.xcworkspace -scheme Whim -configuration Release \
  -destination 'generic/platform=iOS' -archivePath "$whim_archive" \
  CODE_SIGNING_ALLOWED=NO
whim_app="$whim_archive/Products/Applications/whim.app"
./scripts/check-release-fixtures.sh "$whim_app"
./scripts/check-release-privacy.sh "$whim_app"
./scripts/check-release-metadata.sh "$whim_app"
