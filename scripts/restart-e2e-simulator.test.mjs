import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { chmod, mkdtemp, readFile, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { test } from 'node:test';

test('E2E startup closes the stale simulator session and waits for a fresh boot', async t => {
  const root = await mkdtemp(join(tmpdir(), 'whim-simulator-restart-'));
  t.after(() => rm(root, { recursive: true, force: true }));
  const state = join(root, 'state');
  await writeFile(state, 'stale');
  const xcrun = join(root, 'xcrun');
  await writeFile(xcrun, `#!/bin/sh
set -eu
[ "$1" = simctl ] && [ "$3" = fixture-iphone ]
case "$2" in
  shutdown) [ "$(cat "$WHIM_TEST_STATE")" = stale ]; printf shutdown > "$WHIM_TEST_STATE" ;;
  bootstatus) [ "$4" = -b ]; [ "$(cat "$WHIM_TEST_STATE")" = shutdown ]; printf ready > "$WHIM_TEST_STATE"; echo Finished ;;
  *) exit 9 ;;
esac
`);
  await chmod(xcrun, 0o755);
  execFileSync(process.execPath, [new URL('./restart-e2e-simulator.mjs', import.meta.url).pathname, 'fixture-iphone'], {
    env: { ...process.env, PATH: `${root}:${process.env.PATH}`, WHIM_TEST_STATE: state }, stdio: 'pipe',
  });
  assert.equal(await readFile(state, 'utf8'), 'ready');
});

for (const output of ['Status=3, isTerminal=YES\nData Migration Failed', 'Status=4, isTerminal=NO']) {
  test(`E2E startup rejects an unhealthy boot even when simctl exits zero: ${output}`, async t => {
    const { spawnSync } = await import('node:child_process');
    const root = await mkdtemp(join(tmpdir(), 'whim-unhealthy-simulator-'));
    t.after(() => rm(root, { recursive: true, force: true }));
    const xcrun = join(root, 'xcrun');
    await writeFile(xcrun, '#!/bin/sh\nif [ "$2" = bootstatus ]; then printf "%s\\n" "$WHIM_TEST_BOOT_OUTPUT"; fi\nexit 0\n');
    await chmod(xcrun, 0o755);
    const result = spawnSync(process.execPath, [new URL('./restart-e2e-simulator.mjs', import.meta.url).pathname, 'fixture-iphone'], {
      encoding: 'utf8', env: { ...process.env, PATH: `${root}:${process.env.PATH}`, WHIM_TEST_BOOT_OUTPUT: output },
    });
    assert.notEqual(result.status, 0);
    assert.match(result.stderr, /boot.*failed|healthy boot/i);
  });
}

test('E2E startup accepts a simulator booted by another client after shutdown', async t => {
  const { spawnSync } = await import('node:child_process');
  const root = await mkdtemp(join(tmpdir(), 'whim-concurrent-simulator-boot-'));
  t.after(() => rm(root, { recursive: true, force: true }));
  const xcrun = join(root, 'xcrun');
  await writeFile(xcrun, `#!/bin/sh
case "$2" in
  shutdown) exit 0 ;;
  boot) echo 'Unable to boot device in current state: Booted' >&2; exit 149 ;;
  bootstatus) [ "$4" = -b ]; echo 'Device already booted'; exit 0 ;;
  *) exit 9 ;;
esac
`);
  await chmod(xcrun, 0o755);
  const result = spawnSync(process.execPath, [new URL('./restart-e2e-simulator.mjs', import.meta.url).pathname, 'fixture-iphone'], {
    encoding: 'utf8', env: { ...process.env, PATH: `${root}:${process.env.PATH}` },
  });
  assert.equal(result.status, 0, result.stderr);
});

for (const [message, succeeds] of [
  ['Unable to shutdown device in current state: Shutdown', true],
  ['Unable to shutdown device: CoreSimulator service unavailable', false],
]) {
  test(`E2E startup handles shutdown result: ${message}`, async t => {
    const { spawnSync } = await import('node:child_process');
    const root = await mkdtemp(join(tmpdir(), 'whim-shutdown-simulator-'));
    t.after(() => rm(root, { recursive: true, force: true }));
    const xcrun = join(root, 'xcrun');
    await writeFile(xcrun, `#!/bin/sh
case "$2" in
  shutdown) echo "$WHIM_TEST_SHUTDOWN_ERROR" >&2; exit 149 ;;
  bootstatus) echo Finished ;;
  *) exit 9 ;;
esac
`);
    await chmod(xcrun, 0o755);
    const result = spawnSync(process.execPath, [new URL('./restart-e2e-simulator.mjs', import.meta.url).pathname, 'fixture-iphone'], {
      encoding: 'utf8', env: { ...process.env, PATH: `${root}:${process.env.PATH}`, WHIM_TEST_SHUTDOWN_ERROR: message },
    });
    assert.equal(result.status === 0, succeeds, result.stderr);
  });
}
