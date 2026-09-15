#!/usr/bin/env bash
set -euo pipefail

: "${WHIM_WATCH_SIMULATOR_UDID:?Run: eval \"$(./scripts/boot-apple-simulators.sh)\"}"

whim_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$whim_root/scripts/apple-toolchain.sh"
whim_derived_data="${WHIM_DERIVED_DATA_PATH:-$whim_root/ios/build/DerivedData}"

whim_fixture_directory="$(mktemp -d "${TMPDIR:-/tmp}/whim-watch-e2e.XXXXXX")"
python3 - "$whim_fixture_directory/audio.wav" <<'PYTHON'
import math, struct, sys, wave
with wave.open(sys.argv[1], 'wb') as fixture:
    fixture.setparams((1, 2, 16000, 0, 'NONE', 'not compressed'))
    fixture.writeframes(b''.join(struct.pack('<h', int(4000 * math.sin(2 * math.pi * 440 * i / 16000))) for i in range(160000)))
PYTHON
afconvert -f m4af -d aac "$whim_fixture_directory/audio.wav" "$whim_fixture_directory/audio.m4a"
export TEST_RUNNER_WHIM_WATCH_FIXTURE_AUDIO="$whim_fixture_directory/audio.m4a"

whim_webhook_log="$whim_root/ios/build/watch-webhook-e2e.log"
mkdir -p "$(dirname "$whim_webhook_log")"
env WHIM_WEBHOOK_PORT=0 node "$whim_root/packages/WhimCore/Sources/WhimCore/WebhookConfiguration/Fixtures/webhook-server.mjs" >"$whim_webhook_log" 2>&1 &
whim_webhook_pid=$!
trap 'rm -rf "$whim_fixture_directory"; kill "$whim_webhook_pid" 2>/dev/null || true; wait "$whim_webhook_pid" 2>/dev/null || true' EXIT
whim_webhook_port="$(node - "$whim_webhook_log" <<'NODE'
const fs = require('node:fs');
(async () => {
  for (let attempt = 0; attempt < 100; attempt++) {
    try {
      const info = JSON.parse(fs.readFileSync(process.argv[2], 'utf8').split('\n')[0]);
      if (Number.isInteger(info.port)) { process.stdout.write(String(info.port)); return; }
    } catch {}
    await new Promise(resolve => setTimeout(resolve, 50));
  }
  process.exit(1);
})();
NODE
)"
export TEST_RUNNER_WHIM_WATCH_WEBHOOK_URL="http://127.0.0.1:$whim_webhook_port"

xcodebuild test -quiet \
  -workspace "$whim_root/ios/Whim.xcworkspace" \
  -scheme WhimWatchUITests \
  -derivedDataPath "$whim_derived_data" \
  -only-testing:WhimWatchUITests \
  -destination "id=${WHIM_WATCH_SIMULATOR_UDID}" \
  CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=-
