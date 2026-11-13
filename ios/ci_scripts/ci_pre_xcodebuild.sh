#!/bin/bash
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/benchmark_action.sh"
if whim_handle_native_benchmark_test pre; then exit 0; fi
: "${CI_PRIMARY_REPOSITORY_PATH:?Xcode Cloud repository path is required}"
source "$CI_PRIMARY_REPOSITORY_PATH/ios/ci_scripts/ci_environment.sh"
whim_cloud_role="$(node "$CI_PRIMARY_REPOSITORY_PATH/scripts/benchmark-cloud.mjs" role)"
if [[ "$whim_cloud_role" != "functional" ]]; then
  node "$CI_PRIMARY_REPOSITORY_PATH/scripts/xcode-cloud.mjs" pre
  exit
fi
whim_setup_test_dependencies
node "$CI_PRIMARY_REPOSITORY_PATH/scripts/cloud-test-keychain.mjs"
