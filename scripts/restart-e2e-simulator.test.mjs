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
  boot) [ "$(cat "$WHIM_TEST_STATE")" = shutdown ]; printf booting > "$WHIM_TEST_STATE" ;;
  bootstatus) [ "$4" = -b ]; [ "$(cat "$WHIM_TEST_STATE")" = booting ]; printf ready > "$WHIM_TEST_STATE" ;;
  *) exit 9 ;;
esac
`);
  await chmod(xcrun, 0o755);
  execFileSync(process.execPath, [new URL('./restart-e2e-simulator.mjs', import.meta.url).pathname, 'fixture-iphone'], {
    env: { ...process.env, PATH: `${root}:${process.env.PATH}`, WHIM_TEST_STATE: state }, stdio: 'pipe',
  });
  assert.equal(await readFile(state, 'utf8'), 'ready');
});
