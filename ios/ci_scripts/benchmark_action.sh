#!/bin/bash
# Test runners receive native products and ci_scripts resources, not necessarily
# the source checkout or a Node installation. Native XCTest owns its verdict.
whim_handle_native_benchmark_test() {
  local whim_phase="$1"
  if [[ -z "${WHIM_BENCHMARK_WORKFLOW_ID:-}" || "${CI_WORKFLOW_ID:-}" != "$WHIM_BENCHMARK_WORKFLOW_ID" || "${CI_XCODEBUILD_ACTION:-}" != "test-without-building" ]]; then
    return 1
  fi
  if [[ -n "${WHIM_BENCHMARK_GITHUB_TOKEN:-}" || -n "${WHIM_ASC_PRIVATE_KEY:-}" ]]; then
    echo 'Publisher credentials must never be supplied to native benchmark tests.' >&2
    exit 1
  fi
  if [[ -n "${CI_PULL_REQUEST_NUMBER:-}" || -n "${CI_TAG:-}" || ! "${CI_BRANCH:-}" =~ ^benchmark-input/(main|pr/[1-9][0-9]*)/([a-f0-9]{40})$ ]]; then
    echo 'Invalid native benchmark input context.' >&2
    exit 1
  fi
  if [[ "${BASH_REMATCH[2]}" != "${CI_COMMIT:-}" ]]; then
    echo 'Native benchmark input does not match the source commit.' >&2
    exit 1
  fi
  if [[ "$whim_phase" == post && "${CI_XCODEBUILD_EXIT_CODE:-}" != 0 ]]; then
    echo 'Native benchmark Test action failed; results remain in its native result bundle.' >&2
    exit 1
  fi
  return 0
}
