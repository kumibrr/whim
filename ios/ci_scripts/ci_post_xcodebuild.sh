#!/bin/bash
set -euo pipefail
: "${CI_PRIMARY_REPOSITORY_PATH:?Xcode Cloud repository path is required}"
source "$CI_PRIMARY_REPOSITORY_PATH/ios/ci_scripts/ci_environment.sh"
node "$CI_PRIMARY_REPOSITORY_PATH/scripts/xcode-cloud.mjs" post
