import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { test } from 'node:test';

test('release CLI and help only explain GitHub publishing, and reject unsupported arguments', () => {
  const path = new URL('./release.mjs', import.meta.url).pathname;
  for (const args of [[], ['--help']]) {
    const result = spawnSync(process.execPath, [path, ...args], { cwd: '/tmp', encoding: 'utf8' });
    assert.equal(result.status, 0);
    assert.match(result.stdout, /Publish a GitHub Release/);
    assert.match(result.stdout, /runs no local CI/);
  }
  const unknown = spawnSync(process.execPath, [path, '--dry-run'], { encoding: 'utf8' });
  assert.equal(unknown.status, 1);
  assert.match(unknown.stderr, /Unsupported argument/);
});
