import assert from 'node:assert/strict';
import { access } from 'node:fs/promises';
import { test } from 'node:test';

async function fixture(options = {}) {
  const calls = [];
  let keychain;
  const security = async args => {
    calls.push(args);
    if (args[0] === 'list-keychains' && !args.includes('-s')) return '    "/cloud/signing.keychain-db"\n    "/cloud/with spaces/login.keychain-db"\n';
    if (args[0] === 'default-keychain' && !args.includes('-s')) {
      if (options.noDefault) throw Object.assign(Error('Missing default'), { stderr: 'A default keychain could not be found.' });
      if (options.defaultFailure) throw Object.assign(Error('Permission denied'), { stderr: 'Permission denied.' });
      return '    "/cloud/with spaces/login.keychain-db"\n';
    }
    if (args[0] === 'create-keychain') keychain = args.at(-1);
    if (options.fail?.(args, keychain)) throw Error('Injected security failure');
    return '';
  };
  const run = async operation => (await import('./cloud-test-keychain.mjs')).withCloudTestKeychain(operation, { security });
  return { calls, run, get keychain() { return keychain; } };
}

test('Cloud tests get an unlocked disposable default while original signing keychains remain searchable', async () => {
  const f = await fixture();
  const result = await f.run(async () => {
    assert.ok(f.keychain.endsWith('/tests.keychain-db'));
    assert.deepEqual(f.calls.slice(-4), [
      ['set-keychain-settings', f.keychain],
      ['unlock-keychain', '-p', '', f.keychain],
      ['list-keychains', '-d', 'user', '-s', f.keychain, '/cloud/signing.keychain-db', '/cloud/with spaces/login.keychain-db'],
      ['default-keychain', '-d', 'user', '-s', f.keychain],
    ]);
    return 23;
  });
  assert.equal(result, 23);
  assert.deepEqual(f.calls.slice(-3), [
    ['default-keychain', '-d', 'user', '-s', '/cloud/with spaces/login.keychain-db'],
    ['list-keychains', '-d', 'user', '-s', '/cloud/signing.keychain-db', '/cloud/with spaces/login.keychain-db'],
    ['delete-keychain', f.keychain],
  ]);
  await assert.rejects(access(f.keychain), { code: 'ENOENT' });
});

for (const phase of ['operation', 'setup', 'create']) test(`restores keychain state after ${phase} failure`, async () => {
  const f = await fixture({ fail: args => (phase === 'setup' && args[0] === 'unlock-keychain') || (phase === 'create' && args[0] === 'create-keychain') });
  let called = false;
  await assert.rejects(f.run(async () => { called = true; throw Error('Tests failed'); }), phase === 'operation' ? /Tests failed/ : /security failure/);
  assert.equal(called, phase === 'operation');
  assert.equal(f.calls.at(-1)[0], 'delete-keychain');
  assert.ok(f.calls.some(args => args[0] === 'default-keychain' && args.at(-1) === '/cloud/with spaces/login.keychain-db'));
});

test('a Cloud account without a default restores the absent default after tests', async () => {
  const f = await fixture({ noDefault: true });
  await f.run(async () => {});
  assert.deepEqual(f.calls.at(-3), ['default-keychain', '-d', 'user', '-s']);
});

test('an unexpected default-keychain lookup failure stops before changing security state', async () => {
  const f = await fixture({ defaultFailure: true });
  await assert.rejects(f.run(async () => assert.fail('must not run')), /Permission denied/);
  assert.ok(!f.calls.some(args => args[0] === 'create-keychain'));
});

test('a restoration failure still attempts deletion and cannot hide the test failure', async () => {
  const f = await fixture({ fail: args => args[0] === 'default-keychain' && args.at(-1) === '/cloud/with spaces/login.keychain-db' });
  await assert.rejects(f.run(async () => { throw Error('Tests failed'); }), error => {
    assert.match(error.message, /Tests failed/);
    assert.match(error.message, /security failure/);
    return true;
  });
  assert.equal(f.calls.at(-1)[0], 'delete-keychain');
});

for (const role of ['functional', 'measure', 'history']) test(`the ${role} pre-build hook uses only its intended validation boundary`, async t => {
  const { mkdtemp, mkdir, writeFile, readFile, rm } = await import('node:fs/promises');
  const { tmpdir } = await import('node:os');
  const { join } = await import('node:path');
  const { execFile } = await import('node:child_process');
  const { promisify } = await import('node:util');
  const root = await mkdtemp(join(tmpdir(), 'whim-pre-hook-'));
  t.after(() => rm(root, { force: true, recursive: true }));
  await mkdir(join(root, 'bin'));
  await mkdir(join(root, 'ios/ci_scripts'), { recursive: true });
  await writeFile(join(root, 'ios/ci_scripts/ci_environment.sh'), 'whim_setup_test_dependencies() { echo dependencies >> "$WHIM_TEST_LOG"; }\n');
  await writeFile(join(root, 'bin/node'), '#!/bin/bash\nif [[ "${2:-}" == role ]]; then echo "$WHIM_TEST_ROLE"; else basename "$1" >> "$WHIM_TEST_LOG"; fi\n', { mode: 0o755 });
  const output = join(root, 'calls');
  await promisify(execFile)('bash', [new URL('../ios/ci_scripts/ci_pre_xcodebuild.sh', import.meta.url).pathname], {
    env: { PATH: `${join(root, 'bin')}:${process.env.PATH}`, CI_PRIMARY_REPOSITORY_PATH: root, WHIM_TEST_ROLE: role, WHIM_TEST_LOG: output },
  });
  assert.equal(await readFile(output, 'utf8'), role === 'functional' ? 'dependencies\ncloud-test-keychain.mjs\n' : 'xcode-cloud.mjs\n');
});
