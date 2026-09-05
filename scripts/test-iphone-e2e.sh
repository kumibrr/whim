#!/usr/bin/env bash
set -euo pipefail

: "${WHIM_IPHONE_SIMULATOR_UDID:?Run: eval \"$(./scripts/boot-apple-simulators.sh)\"}"

whim_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$whim_root/scripts/apple-toolchain.sh"
whim_derived_data="${WHIM_DERIVED_DATA_PATH:-$whim_root/ios/build/DerivedData}"
whim_metro_log="$whim_root/ios/build/metro-e2e.log"
whim_bundle_id="app.whim.ios"
mkdir -p "$(dirname "$whim_metro_log")"

whim_metro_port="${WHIM_METRO_PORT:-}"
if [[ -z "$whim_metro_port" ]]; then
  whim_metro_port="$(node -e '
    const server = require("node:net").createServer();
    server.listen(0, "127.0.0.1", () => {
      process.stdout.write(String(server.address().port));
      server.close();
    });
  ')"
fi
whim_metro_status_url="http://localhost:$whim_metro_port/status"

whim_maestro="$(command -v maestro || true)"
if [[ -z "$whim_maestro" && -x "$HOME/.maestro/bin/maestro" ]]; then
  whim_maestro="$HOME/.maestro/bin/maestro"
fi
if [[ -z "$whim_maestro" ]]; then
  echo "Maestro is required. Install it from https://maestro.mobile.dev/." >&2
  exit 1
fi

whim_metro_pid=''
whim_cleanup() {
  xcrun simctl terminate "$WHIM_IPHONE_SIMULATOR_UDID" "$whim_bundle_id" >/dev/null 2>&1 || true
  xcrun simctl uninstall "$WHIM_IPHONE_SIMULATOR_UDID" "$whim_bundle_id" >/dev/null 2>&1 || true
  if [[ -n "$whim_metro_pid" ]]; then
    node "$whim_root/scripts/terminate-process-tree.mjs" "$whim_metro_pid" >/dev/null 2>&1 || true
    wait "$whim_metro_pid" >/dev/null 2>&1 || true
  fi
}
trap whim_cleanup EXIT

(
  cd "$whim_root"
  exec env CI=1 npx expo start --dev-client --lan --port "$whim_metro_port"
) >"$whim_metro_log" 2>&1 &
whim_metro_pid=$!

node "$whim_root/scripts/wait-for-metro.mjs" "$whim_metro_status_url" "$whim_metro_pid" || {
  echo "Metro did not become ready. See $whim_metro_log" >&2
  exit 1
}

whim_expo_url="$(curl --fail --silent "http://localhost:$whim_metro_port/_expo/open?platform=ios&runtime=custom" | node -e '
  let input = "";
  process.stdin.on("data", (chunk) => input += chunk);
  process.stdin.on("end", () => {
    const response = JSON.parse(input);
    if (typeof response.url !== "string") process.exit(1);
    process.stdout.write(response.url);
  });
')"
whim_expo_url="${whim_expo_url}&disableOnboarding=1"

xcodebuild build -quiet \
  -workspace "$whim_root/ios/Whim.xcworkspace" \
  -scheme Whim \
  -configuration Debug \
  -derivedDataPath "$whim_derived_data" \
  -destination "id=${WHIM_IPHONE_SIMULATOR_UDID}" \
  CODE_SIGNING_ALLOWED=NO

whim_app="$whim_derived_data/Build/Products/Debug-iphonesimulator/whim.app"
xcrun simctl uninstall "$WHIM_IPHONE_SIMULATOR_UDID" "$whim_bundle_id" >/dev/null 2>&1 || true
xcrun simctl install "$WHIM_IPHONE_SIMULATOR_UDID" "$whim_app"
MAESTRO_CLI_NO_ANALYTICS=1 MAESTRO_CLI_ANALYSIS_NOTIFICATION_DISABLED=true \
  "$whim_maestro" test \
  --device "$WHIM_IPHONE_SIMULATOR_UDID" \
  -e "EXPO_DEV_CLIENT_URL=$whim_expo_url" \
  "$whim_root/e2e/iphone/smoke.e2e.test.yaml"
