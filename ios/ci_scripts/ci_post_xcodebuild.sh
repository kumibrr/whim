#!/bin/bash
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/benchmark_action.sh"
if whim_handle_native_benchmark_test post; then exit 0; fi
: "${CI_PRIMARY_REPOSITORY_PATH:?Xcode Cloud repository path is required}"
source "$CI_PRIMARY_REPOSITORY_PATH/ios/ci_scripts/ci_environment.sh"
node "$CI_PRIMARY_REPOSITORY_PATH/scripts/xcode-cloud.mjs" post
