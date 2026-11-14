#!/usr/bin/env bash
set -euo pipefail
: "${WHIM_IPHONE_SIMULATOR_UDID:?Set an iPhone simulator UDID, or run: eval \"$(./scripts/boot-apple-simulators.sh)\"}"
whim_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$whim_root/scripts/apple-toolchain.sh"
source "$whim_root/scripts/xcode-build-locations.sh"
whim_cache_args=()
if [[ -n "${WHIM_XCODE_PACKAGE_CACHE_PATH:-}" ]]; then
  whim_cache_args=(-packageCachePath "$WHIM_XCODE_PACKAGE_CACHE_PATH")
fi
mkdir -p "$whim_derived_data/Logs/Test"
whim_result_directory="$(mktemp -d "$whim_derived_data/Logs/Test/performance.XXXXXX")"
whim_result="$whim_result_directory/WhimPerformanceTests.xcresult"
echo "Native performance results: $whim_result"
if xcodebuild test -jobs 2 -quiet -workspace "$whim_root/ios/Whim.xcworkspace" \
  -scheme WhimPerformanceTests -configuration DebugBenchmark \
  "${whim_xcode_build_locations[@]}" "${whim_cache_args[@]}" \
  -parallel-testing-enabled NO -destination "id=$WHIM_IPHONE_SIMULATOR_UDID" \
  -resultBundlePath "$whim_result" COMPILER_INDEX_STORE_ENABLE=NO \
  CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=-; then
  node "$whim_root/scripts/benchmark-cloud.mjs" verify-native "$whim_result"
else
  whim_status=$?
  xcrun xcresulttool get test-results summary --path "$whim_result" || true
  node "$whim_root/scripts/benchmark-cloud.mjs" verify-native "$whim_result" || true
  exit "$whim_status"
fi
