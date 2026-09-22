#!/usr/bin/env bash
set -euo pipefail
whim_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$whim_root"
node scripts/check-release-fixtures.mjs "${1:-}"
