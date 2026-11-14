import assert from 'node:assert/strict';
import { chmod, mkdir, mkdtemp, readFile, rm, writeFile } from 'node:fs/promises';
import { execFile } from 'node:child_process';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { promisify } from 'node:util';
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

test('native benchmark actions do not rerun the functional suites or the release archive', async () => {
  for (const action of ['build-for-testing', 'test-without-building']) {
    const { calls, result } = await phase('pre', { CI_XCODEBUILD_ACTION: action, CI_WORKFLOW_ID: 'measure',
      WHIM_BENCHMARK_WORKFLOW_ID: 'measure', CI_BRANCH: `benchmark-input/main/${'a'.repeat(40)}` });
    await result;
    assert.deepEqual(calls, []);
  }
});

test('only the trusted-main history action invokes collection and native failure remains visible', async () => {
  const env = { CI_XCODEBUILD_ACTION: 'build', CI_WORKFLOW_ID: 'history', WHIM_BENCHMARK_HISTORY_WORKFLOW_ID: 'history', CI_BRANCH: 'main' };
  const { calls, result } = await phase('pre', env); await result;
  assert.equal(calls.length, 1); assert.ok(calls[0].args.includes('scripts/benchmark-cloud.mjs'));
  await assert.rejects((await phase('pre', { ...env, CI_PULL_REQUEST_NUMBER: '1' })).result, /trusted main/);
  await assert.rejects((await phase('post', { ...env, CI_XCODEBUILD_EXIT_CODE: '65' })).result, /failed/);
});

test('generated-only main updates skip custom gates but mixed code updates retain the full suite', async () => {
  const { cloudPhase } = await import('./xcode-cloud.mjs');
  for (const mixed of [false, true]) {
    const calls = [];
    await cloudPhase('pre', '/checkout', { env: { CI_BRANCH: 'main', CI_COMMIT: 'a'.repeat(40), CI_XCODEBUILD_ACTION: 'build' },
      run: async (exe, args) => { calls.push([exe, args]); return exe === 'git' ? 'benchmarks/results/run.json\0' + (mixed ? 'src/app.swift\0' : '') : ''; } });
    assert.equal(calls.some(([exe, args]) => exe === 'npm' && args.includes('test:all')), mixed);
  }
});

test('native test-without-building hooks need no source checkout, Node bootstrap, or publisher secrets', async () => {
  const env = { ...process.env, CI_PRIMARY_REPOSITORY_PATH: '/checkout-not-present-in-native-test-action',
    CI_PULL_REQUEST_NUMBER: '', CI_TAG: '', WHIM_ASC_PRIVATE_KEY: '', WHIM_BENCHMARK_GITHUB_TOKEN: '',
    CI_WORKFLOW_ID: 'measure', WHIM_BENCHMARK_WORKFLOW_ID: 'measure', CI_XCODEBUILD_ACTION: 'test-without-building',
    CI_BRANCH: `benchmark-input/main/${'a'.repeat(40)}`, CI_COMMIT: 'a'.repeat(40), CI_XCODEBUILD_EXIT_CODE: '0' };
  const executeHook = (name, extra = {}) => promisify(execFile)('bash', [new URL(`../ios/ci_scripts/ci_${name}_xcodebuild.sh`, import.meta.url).pathname], { env: { ...env, ...extra } });
  await executeHook('pre'); await executeHook('post');
  await assert.rejects(executeHook('post', { CI_XCODEBUILD_EXIT_CODE: '65' }));
  for (const context of [{ CI_PULL_REQUEST_NUMBER: '59' }, { CI_TAG: '1.2.3' }]) {
    await assert.rejects(executeHook('pre', context), { stderr: /Invalid native benchmark input context/ });
  }
  for (const credentials of [{ WHIM_ASC_PRIVATE_KEY: 'synthetic-private-key' }, { WHIM_BENCHMARK_GITHUB_TOKEN: 'synthetic-token' }]) {
    await assert.rejects(executeHook('pre', credentials), { stderr: /Publisher credentials must never be supplied/ });
  }
});

test('native hook fixture isolates its context from the enclosing Cloud action', async () => {
  for (const enclosingAction of [
    { CI_PULL_REQUEST_NUMBER: '59' }, { CI_TAG: '1.2.3' },
    { WHIM_ASC_PRIVATE_KEY: 'synthetic-host-private-key' },
    { WHIM_BENCHMARK_GITHUB_TOKEN: 'synthetic-host-token' },
  ]) {
    const { stdout } = await promisify(execFile)(process.execPath, [
      '--test', '--test-reporter=tap', '--test-name-pattern', '^native test-without-building hooks need no source checkout',
      new URL('./xcode-cloud.test.mjs', import.meta.url).pathname,
    ], { env: { ...process.env, NODE_TEST_CONTEXT: undefined, ...enclosingAction } });
    assert.match(stdout, /# pass 1\b/);
  }
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

const execute = promisify(execFile);

async function runWatchTests(t, testStatus, summaryStatus = 0) {
  const root = await mkdtemp(join(tmpdir(), 'whim-watch-runner-'));
  t.after(() => rm(root, { recursive: true, force: true }));
  const bin = join(root, 'bin');
  await mkdir(bin);
  async function command(name, source) {
    const path = join(bin, name);
    await writeFile(path, `#!/usr/bin/env node\n${source}`);
    await chmod(path, 0o755);
  }
  // Mock only the native codec/Xcode process boundaries. The runner and its
  // loopback webhook server execute normally, including EXIT cleanup.
  for (const name of ['python3', 'afconvert']) {
    await command(name, `require('node:fs').writeFileSync(process.argv.at(-1), 'fixture');`);
  }
  await command('xcodebuild', `
    const fs = require('node:fs');
    const args = process.argv.slice(2);
    fs.writeFileSync(process.env.WHIM_TEST_XCODE_ARGS, JSON.stringify(args));
    const index = args.indexOf('-resultBundlePath');
    if (index >= 0) fs.mkdirSync(args[index + 1], { recursive: true });
    process.exit(Number(process.env.WHIM_TEST_XCODE_STATUS));
  `);
  await command('xcrun', `
    const fs = require('node:fs');
    fs.writeFileSync(process.env.WHIM_TEST_SUMMARY_ARGS, JSON.stringify(process.argv.slice(2)));
    console.log(JSON.stringify({ testFailures: [{
      testName: 'WatchRecordingUITests.testDiscardImmediatelyLeavesNoNote()',
      failureText: 'Expected the Discard control to be at least 100 points wide.'
    }] }));
    process.exit(Number(process.env.WHIM_TEST_SUMMARY_STATUS));
  `);
  const env = { ...process.env, PATH: `${bin}:${process.env.PATH}`,
    WHIM_DERIVED_DATA_PATH: join(root, 'Derived Data'), WHIM_WATCH_SIMULATOR_UDID: 'fixture-watch',
    WHIM_TEST_XCODE_ARGS: join(root, 'xcode-args.json'), WHIM_TEST_SUMMARY_ARGS: join(root, 'summary-args.json'),
    WHIM_TEST_XCODE_STATUS: String(testStatus), WHIM_TEST_SUMMARY_STATUS: String(summaryStatus) };
  let result;
  try {
    result = { code: 0, ...await execute('bash', [new URL('./test-watch-e2e.sh', import.meta.url).pathname],
      { env, timeout: 15_000 }) };
  } catch (error) { result = error; }
  const args = await readFile(env.WHIM_TEST_XCODE_ARGS, 'utf8').catch(error => {
    throw new Error(`Watch runner did not reach xcodebuild (exit ${result.code}): ${result.stderr}`, { cause: error });
  });
  return { result, env, args: JSON.parse(args) };
}

test('failed Watch UI tests expose native assertion details and retain the failing exit status', async t => {
  const { result, env, args } = await runWatchTests(t, 65);
  assert.equal(result.code, 65);
  assert.match(result.stdout, /Expected the Discard control to be at least 100 points wide/);
  const bundle = args[args.indexOf('-resultBundlePath') + 1];
  assert.ok(bundle.endsWith('.xcresult'));
  assert.deepEqual(JSON.parse(await readFile(env.WHIM_TEST_SUMMARY_ARGS, 'utf8')),
    ['xcresulttool', 'get', 'test-results', 'summary', '--path', bundle]);
});

test('a failure to read Watch diagnostics cannot replace the original test failure', async t => {
  const { result, env } = await runWatchTests(t, 65, 2);
  assert.equal(result.code, 65);
  assert.ok(await readFile(env.WHIM_TEST_SUMMARY_ARGS, 'utf8'));
});

test('successful Watch UI tests do not request failure diagnostics', async t => {
  const { result, env } = await runWatchTests(t, 0);
  assert.equal(result.code, 0);
  await assert.rejects(readFile(env.WHIM_TEST_SUMMARY_ARGS), { code: 'ENOENT' });
});
