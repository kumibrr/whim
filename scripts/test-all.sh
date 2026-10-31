#!/usr/bin/env bash
set -euo pipefail

whim_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$whim_root"

if [[ "$(uname -s)" == "Darwin" && (
  -z "${WHIM_IPHONE_SIMULATOR_UDID:-}" || -z "${WHIM_WATCH_SIMULATOR_UDID:-}"
) ]]; then
  whim_simulator_environment="$(./scripts/boot-apple-simulators.sh)"
  eval "$whim_simulator_environment"
fi

node scripts/check-test-colocation.mjs
npm run test:unit
npm run test:integration
npm run test:e2e
