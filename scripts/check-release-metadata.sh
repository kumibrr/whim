#!/usr/bin/env bash
set -euo pipefail
whim_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
node "$whim_root/scripts/check-release-metadata.mjs" "$whim_root" "$@"
