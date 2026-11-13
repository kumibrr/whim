import assert from 'node:assert/strict';
import { test } from 'node:test';

test('Cloud input refs must match the exact checked-out source and cannot claim another context', async () => {
  const { sourceContext } = await import('./benchmark-input.mjs');
  const sha = 'a'.repeat(40);
  assert.equal(sourceContext({ CI: 'TRUE', CI_BRANCH: `benchmark-input/main/${sha}`, CI_COMMIT: sha }, sha), 'main');
  assert.equal(sourceContext({ CI: 'TRUE', CI_BRANCH: `benchmark-input/pr/42/${sha}`, CI_COMMIT: sha }, sha), 'pr/42');
  assert.equal(sourceContext({}, sha), 'local');
  for (const env of [{ CI: 'TRUE', CI_BRANCH: 'main', CI_COMMIT: sha },
    { CI: 'TRUE', CI_BRANCH: `benchmark-input/main/${'b'.repeat(40)}`, CI_COMMIT: sha },
    { CI: 'TRUE', CI_BRANCH: `benchmark-input/pr/0/${sha}`, CI_COMMIT: sha }]) {
    assert.throws(() => sourceContext(env, sha), /source|input|context/i);
  }
});
