#!/usr/bin/env bash
set -euo pipefail

whim_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$whim_root/scripts/apple-toolchain.sh"

whim_simulator_data="$(mktemp -d "${TMPDIR:-/tmp}/whim-simulators.XXXXXX")"
trap 'rm -rf "$whim_simulator_data"' EXIT

xcrun simctl list runtimes --json > "$whim_simulator_data/runtimes.json"
xcrun simctl list devicetypes --json > "$whim_simulator_data/device-types.json"
xcrun simctl list devices --json > "$whim_simulator_data/devices.json"

whim_device_type() {
  WHIM_PRODUCT_FAMILY="$1" node - "$whim_simulator_data/device-types.json" <<'NODE'
const fs = require('node:fs');
const types = JSON.parse(fs.readFileSync(process.argv[2], 'utf8')).devicetypes;
const match = types.find((type) => type.productFamily === process.env.WHIM_PRODUCT_FAMILY);
if (!match) process.exit(1);
process.stdout.write(match.identifier);
NODE
}

whim_existing_device() {
  WHIM_DEVICE_NAME="$1" WHIM_RUNTIME_ID="$2" node - "$whim_simulator_data/devices.json" <<'NODE'
const fs = require('node:fs');
const devices = JSON.parse(fs.readFileSync(process.argv[2], 'utf8')).devices;
const match = (devices[process.env.WHIM_RUNTIME_ID] ?? []).find(
  (device) => device.isAvailable && device.name === process.env.WHIM_DEVICE_NAME,
);
if (match) process.stdout.write(match.udid);
NODE
}

whim_runtime_selection="$(node "$whim_root/scripts/select-apple-runtimes.mjs" "$whim_simulator_data/runtimes.json")" || {
  echo "Install a compatible simulator pair in Xcode at $DEVELOPER_DIR." >&2
  exit 1
}
whim_ios_runtime="${whim_runtime_selection%%|*}"
whim_watch_runtime="${whim_runtime_selection#*|}"
whim_iphone_type="$(whim_device_type iPhone)" || {
  echo "No iPhone simulator device type is installed." >&2
  exit 1
}
whim_watch_type="$(whim_device_type 'Apple Watch')" || {
  echo "No Apple Watch simulator device type is installed." >&2
  exit 1
}

whim_iphone_name="Whim CI iPhone"
whim_watch_name="Whim CI Watch"
whim_iphone_udid="$(whim_existing_device "$whim_iphone_name" "$whim_ios_runtime")"
whim_watch_udid="$(whim_existing_device "$whim_watch_name" "$whim_watch_runtime")"

if [[ -z "$whim_iphone_udid" ]]; then
  whim_iphone_udid="$(xcrun simctl create "$whim_iphone_name" "$whim_iphone_type" "$whim_ios_runtime")"
fi
if [[ -z "$whim_watch_udid" ]]; then
  whim_watch_udid="$(xcrun simctl create "$whim_watch_name" "$whim_watch_type" "$whim_watch_runtime")"
fi

if ! xcrun simctl list pairs --json | WHIM_IPHONE="$whim_iphone_udid" WHIM_WATCH="$whim_watch_udid" node -e '
  let input = "";
  process.stdin.on("data", (chunk) => input += chunk);
  process.stdin.on("end", () => {
    const pairs = Object.values(JSON.parse(input).pairs);
    process.exit(pairs.some((pair) => pair.phone.udid === process.env.WHIM_IPHONE && pair.watch.udid === process.env.WHIM_WATCH) ? 0 : 1);
  });
'; then
  if ! whim_pair_error="$(xcrun simctl pair "$whim_watch_udid" "$whim_iphone_udid" 2>&1)"; then
    echo "The selected runtimes could not be paired: $whim_ios_runtime with $whim_watch_runtime." >&2
    echo "$whim_pair_error" >&2
    exit 1
  fi
fi

xcrun simctl boot "$whim_iphone_udid" >/dev/null 2>&1 || true
xcrun simctl boot "$whim_watch_udid" >/dev/null 2>&1 || true
xcrun simctl bootstatus "$whim_iphone_udid" -b >&2
xcrun simctl bootstatus "$whim_watch_udid" -b >&2

printf "export DEVELOPER_DIR='%s'\n" "$DEVELOPER_DIR"
printf "export WHIM_IPHONE_SIMULATOR_UDID='%s'\n" "$whim_iphone_udid"
printf "export WHIM_WATCH_SIMULATOR_UDID='%s'\n" "$whim_watch_udid"
