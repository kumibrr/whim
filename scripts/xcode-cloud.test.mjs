import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { test } from 'node:test';

async function phase(name, env = {}, failure) {
  const calls = [];
  const { cloudPhase } = await import('./xcode-cloud.mjs');
  const result = cloudPhase(name, '/checkout', { env, run: async (exe, args, options) => {
    calls.push({ exe, args, cwd: options.cwd });
    if (failure?.(exe, args)) throw Error('Boundary failed');
    return '';
  } });
  return { calls, result };
}

test('every cloud pre-build runs tooling, Apple integration and both E2E suites via test:all', async () => {
  const { calls, result } = await phase('pre', { CI_XCODEBUILD_ACTION: 'archive' });
  await result;
  assert.deepEqual(calls.map(c => [c.exe, c.args]), [
    ['npm', ['ci', '--no-audit', '--no-fund']],
    ['bash', ['scripts/check-release-privacy.sh']],
    ['bash', ['scripts/check-release-metadata.sh']],
    ['npm', ['run', 'test:all']],
  ]);
  assert.ok(calls.every(c => c.cwd === '/checkout'));
});

test('PR build actions also validate a clean release archive; archive actions reuse the native archive', async () => {
  const { calls, result } = await phase('pre', { CI_XCODEBUILD_ACTION: 'build' });
  await result;
  assert.deepEqual(calls.at(-1), { exe: 'npm', args: ['run', 'verify:release'], cwd: '/checkout' });
});

test('failed full test suite blocks the native cloud build', async () => {
  const { result } = await phase('pre', { CI_XCODEBUILD_ACTION: 'archive' }, (exe, args) => args.includes('test:all'));
  await assert.rejects(result, /Boundary failed/);
});

test('post-build checks all embedded bundles in the actual native archive', async () => {
  const { calls, result } = await phase('post', { CI_XCODEBUILD_ACTION: 'archive', CI_XCODEBUILD_EXIT_CODE: '0', CI_ARCHIVE_PATH: '/cloud/native.xcarchive' });
  await result;
  assert.deepEqual(calls.map(c => c.args), [
    ['scripts/check-release-fixtures.sh', '/cloud/native.xcarchive/Products/Applications/whim.app'],
    ['scripts/check-release-privacy.sh', '/cloud/native.xcarchive/Products/Applications/whim.app'],
    ['scripts/check-release-metadata.sh', '/cloud/native.xcarchive/Products/Applications/whim.app'],
  ]);
});

for (const env of [
  { CI_XCODEBUILD_ACTION: 'archive', CI_XCODEBUILD_EXIT_CODE: '65' },
  { CI_XCODEBUILD_ACTION: 'archive', CI_XCODEBUILD_EXIT_CODE: '0' },
  { CI_XCODEBUILD_ACTION: 'test-without-building' },
]) test(`cloud fails closed for incomplete action state ${JSON.stringify(env)}`, async () => {
  const { result } = await phase(env.CI_XCODEBUILD_ACTION === 'test-without-building' ? 'pre' : 'post', env);
  await assert.rejects(result, /failed|archive|action/i);
});

test('local release helper is read-only and sends the user to GitHub publishing', async () => {
  const { release } = await import('./release.mjs');
  const messages = [];
  await release('/unused', { run: () => { throw Error('Local commands must not run'); }, log: message => messages.push(message) });
  assert.match(messages.join('\n'), /GitHub Release|GitHub release/);
  assert.match(messages.join('\n'), /release-build\//);
});

test('Actions only prepares manual releases and resumes landed preparations; cloud hooks are executable', async () => {
  const workflow = await readFile(new URL('../.github/workflows/release.yml', import.meta.url), 'utf8');
  assert.match(workflow, /published/);
  assert.match(workflow, /workflow_dispatch/);
  assert.match(workflow, /cancel-in-progress: false/);
  assert.doesNotMatch(workflow, /test:|verify:release|macos-|xcodebuild/);
  assert.match(workflow, /ref: main/);
  assert.match(workflow, /--resume/);
});

for (const phaseName of ['clone', 'pre']) {
  test(`release workflow rejects manually selected unprepared source during ${phaseName}`, async () => {
    const { result } = await phase(phaseName, { CI_WORKFLOW: 'Release', CI_BRANCH: 'main', CI_XCODEBUILD_ACTION: 'archive' });
    await assert.rejects(result, /prepared.*branch|release-build/);
  });
}

test('raw tag cloud starts fail instead of racing preparation', async () => {
  const { result } = await phase('clone', { CI_TAG: '1.0.1' });
  await assert.rejects(result, /Tag-triggered/);
});

test('each hook restores its own tool environment and the pre-hook installs test dependencies', async () => {
  const { access, constants } = await import('node:fs/promises');
  for (const name of ['post_clone', 'pre_xcodebuild', 'post_xcodebuild']) {
    const url = new URL(`../ios/ci_scripts/ci_${name}.sh`, import.meta.url);
    await access(url, constants.X_OK);
    const shell = await readFile(url, 'utf8');
    assert.match(shell, /CI_PRIMARY_REPOSITORY_PATH/);
    assert.match(shell, /source .*ci_environment\.sh/);
    if (name === 'pre_xcodebuild') assert.match(shell, /whim_setup_test_dependencies/);
  }
});

test('fresh cloud environment installs Node 24, Java 17 and verified Maestro without sudo', async t => {
  const { chmod, mkdir, mkdtemp, rm, writeFile } = await import('node:fs/promises');
  const { tmpdir } = await import('node:os');
  const { join } = await import('node:path');
  const { spawnSync } = await import('node:child_process');
  const root = await mkdtemp(join(tmpdir(), 'whim-cloud-bootstrap-'));
  t.after(() => rm(root, { recursive: true, force: true }));
  const bin = join(root, 'bin');
  await mkdir(bin);
  const mock = async (path, body) => { await writeFile(path, '#!/bin/bash\nset -eu\n' + body); await chmod(path, 0o755); };
  await mock(join(bin, 'brew'), `
if [[ "$1" == --prefix ]]; then echo "$WHIM_TEST_ROOT/brew"; exit; fi
echo "$*" >> "$WHIM_TEST_ROOT/commands"
if [[ "$2" == node@24 ]]; then
  mkdir -p "$WHIM_TEST_ROOT/brew/opt/node@24/bin"
  printf '#!/bin/sh\\nexit 0\\n' > "$WHIM_TEST_ROOT/brew/opt/node@24/bin/node"
  chmod +x "$WHIM_TEST_ROOT/brew/opt/node@24/bin/node"
else
  mkdir -p "$WHIM_TEST_ROOT/brew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home/bin"
  printf '#!/bin/sh\\nexit 0\\n' > "$WHIM_TEST_ROOT/brew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home/bin/java"
  chmod +x "$WHIM_TEST_ROOT/brew/opt/openjdk@17/libexec/openjdk.jdk/Contents/Home/bin/java"
fi
`);
  await mock(join(bin, 'curl'), 'echo "$*" >> "$WHIM_TEST_ROOT/commands"\nwhile [[ "$1" != --output ]]; do shift; done\ntouch "$2"\n');
  await mock(join(bin, 'shasum'), 'cat >> "$WHIM_TEST_ROOT/commands"\nif [[ "${WHIM_TEST_BAD_CHECKSUM:-0}" == 1 ]]; then exit 1; fi\n');
  await mock(join(bin, 'unzip'), 'mkdir -p "$4/maestro/bin"\nprintf \'#!/bin/sh\\nexit 0\\n\' > "$4/maestro/bin/maestro"\nchmod +x "$4/maestro/bin/maestro"\n');
  const shell = new URL('../ios/ci_scripts/ci_environment.sh', import.meta.url).pathname;
  const run = bad => spawnSync('bash', ['-c', 'source "$1"; whim_setup_test_dependencies', 'bootstrap', shell], { encoding: 'utf8', env: { ...process.env, HOME: join(root, 'home'), WHIM_TEST_ROOT: root, WHIM_TEST_BAD_CHECKSUM: bad ? '1' : '0', PATH: `${bin}:/usr/bin:/bin` } });
  const first = run(false);
  assert.equal(first.status, 0, first.stderr);
  const commands = await readFile(join(root, 'commands'), 'utf8');
  assert.match(commands, /install node@24/);
  assert.match(commands, /install openjdk@17/);
  assert.match(commands, /cli-2\.10\.0\/maestro\.zip/);
  assert.match(commands, /29b675e10cc12080e445e9bfb2e2b4e4dfb9c0f2e30d5884120d258b5e1cd991/);
  assert.equal(run(true).status, 1, 'a failed checksum must block the hook');
});
