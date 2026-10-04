#!/usr/bin/env bash
set -euo pipefail

: "${WHIM_IPHONE_SIMULATOR_UDID:?Run: eval \"$(./scripts/boot-apple-simulators.sh)\"}"

whim_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$whim_root/scripts/apple-toolchain.sh"
source "$whim_root/scripts/xcode-build-locations.sh"
whim_webhook_log="$whim_root/ios/build/webhook-e2e.log"
whim_bundle_id="app.whim.ios"
mkdir -p "$(dirname "$whim_webhook_log")"

whim_maestro="$(command -v maestro || true)"
if [[ -z "$whim_maestro" && -x "$HOME/.maestro/bin/maestro" ]]; then
  whim_maestro="$HOME/.maestro/bin/maestro"
fi
if [[ -z "$whim_maestro" ]]; then
  echo "Maestro is required. Install it from https://maestro.mobile.dev/." >&2
  exit 1
fi

whim_peer_fixture_directory="$(mktemp -d "${TMPDIR:-/tmp}/whim-peer-e2e.XXXXXX")"
python3 - "$whim_peer_fixture_directory/audio.wav" <<'PYTHON'
import math, struct, sys, wave
with wave.open(sys.argv[1], 'wb') as fixture:
    fixture.setparams((1, 2, 16000, 0, 'NONE', 'not compressed'))
    fixture.writeframes(b''.join(struct.pack('<h', int(4000 * math.sin(2 * math.pi * 440 * i / 16000))) for i in range(160000)))
PYTHON
afconvert -f m4af -d aac "$whim_peer_fixture_directory/audio.wav" "$whim_peer_fixture_directory/audio.m4a"

whim_webhook_pid=''
whim_cleanup() {
  rm -rf "$whim_peer_fixture_directory"
  xcrun simctl terminate "$WHIM_IPHONE_SIMULATOR_UDID" "$whim_bundle_id" >/dev/null 2>&1 || true
  xcrun simctl uninstall "$WHIM_IPHONE_SIMULATOR_UDID" "$whim_bundle_id" >/dev/null 2>&1 || true
  if [[ -n "$whim_webhook_pid" ]]; then
    node "$whim_root/scripts/terminate-process-tree.mjs" "$whim_webhook_pid" >/dev/null 2>&1 || true
    wait "$whim_webhook_pid" >/dev/null 2>&1 || true
  fi
}
trap whim_cleanup EXIT

env WHIM_WEBHOOK_PORT=0 \
  node "$whim_root/packages/WhimCore/Sources/WhimCore/WebhookConfiguration/Fixtures/webhook-server.mjs" \
  >"$whim_webhook_log" 2>&1 &
whim_webhook_pid=$!
whim_webhook_port="$(node - "$whim_webhook_log" "$whim_webhook_pid" <<'NODE'
const fs = require('node:fs');
const [log, pidText] = process.argv.slice(2);
const pid = Number(pidText);
(async () => {
  for (let attempt = 0; attempt < 100; attempt += 1) {
    try {
      const line = fs.readFileSync(log, 'utf8').split('\n')[0];
      const value = JSON.parse(line);
      if (Number.isInteger(value.port)) {
        process.stdout.write(String(value.port));
        return;
      }
    } catch {}
    try { process.kill(pid, 0); } catch { process.exit(1); }
    await new Promise((resolve) => setTimeout(resolve, 50));
  }
  process.exit(1);
})();
NODE
)" || {
  echo "Loopback webhook did not become ready. See $whim_webhook_log" >&2
  exit 1
}

if [[ "${WHIM_IPHONE_E2E_SKIP_BUILD:-0}" != "1" ]]; then
# Xcode embeds simulated entitlements required by the real Keychain boundary.
xcodebuild build -quiet \
  -workspace "$whim_root/ios/Whim.xcworkspace" \
  -scheme Whim \
  -configuration Debug \
  "${whim_xcode_build_locations[@]}" \
  -destination "id=${WHIM_IPHONE_SIMULATOR_UDID}" \
  CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=-
fi

whim_resolve_build_locations "$whim_derived_data" "id=${WHIM_IPHONE_SIMULATOR_UDID}"
whim_app="$whim_build_products/Debug-iphonesimulator/whim.app"
xcrun simctl uninstall "$WHIM_IPHONE_SIMULATOR_UDID" "$whim_bundle_id" >/dev/null 2>&1 || true
xcrun simctl install "$WHIM_IPHONE_SIMULATOR_UDID" "$whim_app"
whim_flows=(
  "$whim_root/e2e/iphone/history-sheet.e2e.test.yaml"
  "$whim_root/e2e/iphone/playback-error.e2e.test.yaml"
  "$whim_root/e2e/iphone/onboarding.e2e.test.yaml"
  "$whim_root/e2e/iphone/onboarding-resume.e2e.test.yaml"
  "$whim_root/e2e/iphone/onboarding-webhook.e2e.test.yaml"
  "$whim_root/e2e/iphone/record-and-review.e2e.test.yaml"
  "$whim_root/e2e/iphone/offline-and-retry.e2e.test.yaml"
  "$whim_root/e2e/iphone/failed-and-retry.e2e.test.yaml"
  "$whim_root/e2e/iphone/recovered-review.e2e.test.yaml"
  "$whim_root/e2e/iphone/settings-and-reset.e2e.test.yaml"
  "$whim_root/e2e/iphone/retention.e2e.test.yaml"
  "$whim_root/e2e/iphone/watch-synchronization.e2e.test.yaml"
  "$whim_root/e2e/iphone/cold-links.e2e.test.yaml"
  "$whim_root/e2e/iphone/shortcuts-and-live-activity.e2e.test.yaml"
)
if [[ -n "${WHIM_IPHONE_E2E_FLOW:-}" ]]; then
  whim_flows=("$whim_root/e2e/iphone/$WHIM_IPHONE_E2E_FLOW")
fi
MAESTRO_CLI_NO_ANALYTICS=1 MAESTRO_CLI_ANALYSIS_NOTIFICATION_DISABLED=true \
  "$whim_maestro" test \
  --device "$WHIM_IPHONE_SIMULATOR_UDID" \
  -e "WHIM_WEBHOOK_TEST_URL=http://127.0.0.1:$whim_webhook_port/receive" \
  -e "WHIM_WEBHOOK_RESET_URL=http://127.0.0.1:$whim_webhook_port/reset" \
  -e "WHIM_WEBHOOK_RESPONSE_URL=http://127.0.0.1:$whim_webhook_port/response" \
  -e "WHIM_PEER_FIXTURE_AUDIO=$whim_peer_fixture_directory/audio.m4a" \
  -e "WHIM_FIXTURE_AUDIO=$whim_peer_fixture_directory/audio.m4a" \
  "${whim_flows[@]}"
