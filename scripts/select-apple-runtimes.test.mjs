import assert from 'node:assert/strict';
import test from 'node:test';

import { selectCompatibleRuntimes } from './select-apple-runtimes.mjs';

function runtime(family, version, isAvailable = true) {
  return {
    identifier: `com.apple.CoreSimulator.SimRuntime.${family}-${version.replaceAll('.', '-')}`,
    isAvailable,
    version,
  };
}

test('selects the newest compatible supported iOS and watchOS pair', () => {
  const selection = selectCompatibleRuntimes([
    runtime('iOS', '17.5'),
    runtime('iOS', '18.6'),
    runtime('iOS', '26.0'),
    runtime('watchOS', '10.6'),
    runtime('watchOS', '26.0'),
    runtime('watchOS', '27.0'),
  ]);

  assert.equal(selection.ios.version, '26.0');
  assert.equal(selection.watch.version, '26.0');
});

test('supports the pre-renumbering iOS 18 and watchOS 11 pairing', () => {
  const selection = selectCompatibleRuntimes([
    runtime('iOS', '18.0'),
    runtime('watchOS', '11.0'),
  ]);

  assert.equal(selection.ios.version, '18.0');
  assert.equal(selection.watch.version, '11.0');
});

test('ignores unavailable runtimes and fails clearly without a supported pair', () => {
  assert.throws(
    () =>
      selectCompatibleRuntimes([
        runtime('iOS', '27.0', false),
        runtime('iOS', '17.5'),
        runtime('watchOS', '27.0'),
        runtime('watchOS', '10.6'),
      ]),
    /No compatible simulator pair.*iOS 18.*watchOS 11/,
  );
});

test('selects device types compatible with the chosen runtimes instead of the first installed model', async () => {
  const { selectCompatibleDeviceType } = await import('./select-apple-runtimes.mjs');
  const types = [
    { identifier: 'new-iphone', productFamily: 'iPhone', minRuntimeVersion: 27 * 65536, maxRuntimeVersion: 0xFFFFFFFF },
    { identifier: 'old-iphone', productFamily: 'iPhone', minRuntimeVersion: 18 * 65536, maxRuntimeVersion: 26 * 65536 },
    { identifier: 'new-watch', productFamily: 'Apple Watch', minRuntimeVersion: 27 * 65536, maxRuntimeVersion: 0xFFFFFFFF },
    { identifier: 'old-watch', productFamily: 'Apple Watch', minRuntimeVersion: 11 * 65536, maxRuntimeVersion: 26 * 65536 },
  ];
  assert.equal(selectCompatibleDeviceType(types, 'iPhone', runtime('iOS', '18.6')).identifier, 'old-iphone');
  assert.equal(selectCompatibleDeviceType(types, 'Apple Watch', runtime('watchOS', '11.6')).identifier, 'old-watch');
  assert.equal(selectCompatibleDeviceType(types, 'iPhone', runtime('iOS', '27.0')).identifier, 'new-iphone');
  assert.throws(() => selectCompatibleDeviceType(types, 'iPhone', runtime('iOS', '17.0')), /No compatible iPhone.*17.0/);
});

test('the full test runner stops immediately when paired simulator setup fails', async t => {
  const { chmod, cp, mkdir, mkdtemp, readFile, rm, writeFile } = await import('node:fs/promises');
  const { tmpdir } = await import('node:os');
  const { join } = await import('node:path');
  const { spawnSync } = await import('node:child_process');
  const root = await mkdtemp(join(tmpdir(), 'whim-failed-simulator-setup-'));
  t.after(() => rm(root, { recursive: true, force: true }));
  await mkdir(join(root, 'scripts'));
  await mkdir(join(root, 'bin'));
  await cp(new URL('./test-all.sh', import.meta.url), join(root, 'scripts/test-all.sh'));
  for (const [name, body] of [
    ['scripts/boot-apple-simulators.sh', 'echo "Incompatible device" >&2; exit 42'],
    ['bin/uname', 'echo Darwin'],
    ['bin/node', 'echo node >> "$WHIM_SETUP_LOG"'],
    ['bin/npm', 'echo npm >> "$WHIM_SETUP_LOG"'],
  ]) {
    await writeFile(join(root, name), '#!/bin/bash\n' + body + '\n');
    await chmod(join(root, name), 0o755);
  }
  const log = join(root, 'commands');
  const result = spawnSync('bash', [join(root, 'scripts/test-all.sh')], { encoding: 'utf8', env: {
    ...process.env, PATH: `${root}/bin:/usr/bin:/bin`, WHIM_SETUP_LOG: log,
    WHIM_IPHONE_SIMULATOR_UDID: '', WHIM_WATCH_SIMULATOR_UDID: '',
  } });
  assert.equal(result.status, 42, result.stderr);
  await assert.rejects(readFile(log), { code: 'ENOENT' });
});

test('paired simulator bootstrap passes compatible device types to simctl and exports both destinations', async t => {
  const { chmod, mkdir, mkdtemp, readFile, rm, writeFile } = await import('node:fs/promises');
  const { tmpdir } = await import('node:os');
  const { join } = await import('node:path');
  const { spawnSync } = await import('node:child_process');
  const root = await mkdtemp(join(tmpdir(), 'whim-compatible-simulators-'));
  t.after(() => rm(root, { recursive: true, force: true }));
  await mkdir(join(root, 'bin'));
  await mkdir(join(root, 'Xcode/usr/bin'), { recursive: true });
  const executable = async (path, body) => { await writeFile(path, '#!/bin/bash\nset -eu\n' + body); await chmod(path, 0o755); };
  await executable(join(root, 'Xcode/usr/bin/xcodebuild'), 'exit 0\n');
  await executable(join(root, 'bin/uname'), 'echo Darwin\n');
  const types = ['iPhone', 'Apple Watch'].flatMap((family, i) => [
    { identifier: `new-${i}`, productFamily: family, minRuntimeVersion: (i ? 11 : 18) * 65536, maxRuntimeVersion: 0xFFFFFFFF },
    { identifier: `supported-${i}`, productFamily: family, minRuntimeVersion: (i ? 11 : 18) * 65536, maxRuntimeVersion: 26 * 65536 },
  ]);
  await writeFile(join(root, 'runtimes.json'), JSON.stringify({ runtimes: [runtime('iOS', '18.6'), runtime('watchOS', '11.6')].map((value, i) => ({ ...value, supportedDeviceTypes: [{ identifier: `supported-${i}` }] })) }));
  await writeFile(join(root, 'types.json'), JSON.stringify({ devicetypes: types }));
  await executable(join(root, 'bin/xcrun'), `
echo "$*" >> "$WHIM_SIMULATOR_FIXTURE/commands"
case "$*" in
  'simctl list runtimes --json') cat "$WHIM_SIMULATOR_FIXTURE/runtimes.json";;
  'simctl list devicetypes --json') cat "$WHIM_SIMULATOR_FIXTURE/types.json";;
  'simctl list devices --json') echo '{"devices":{}}';;
  'simctl list pairs --json') echo '{"pairs":{}}';;
  'simctl create Whim CI iPhone supported-0 com.apple.CoreSimulator.SimRuntime.iOS-18-6') echo iphone-udid;;
  'simctl create Whim CI Watch supported-1 com.apple.CoreSimulator.SimRuntime.watchOS-11-6') echo watch-udid;;
  'simctl create '*) echo 'Incompatible device' >&2; exit 42;;
  'simctl pair watch-udid iphone-udid'|'simctl boot iphone-udid'|'simctl boot watch-udid'|'simctl bootstatus iphone-udid -b'|'simctl bootstatus watch-udid -b') exit 0;;
  *) echo "Unexpected boundary call: $*" >&2; exit 1;;
esac
`);
  const result = spawnSync('bash', [new URL('./boot-apple-simulators.sh', import.meta.url).pathname], { encoding: 'utf8', env: {
    ...process.env, PATH: `${root}/bin:${process.env.PATH}`, DEVELOPER_DIR: join(root, 'Xcode'), WHIM_SIMULATOR_FIXTURE: root,
  } });
  assert.equal(result.status, 0, result.stderr);
  assert.match(result.stdout, /WHIM_IPHONE_SIMULATOR_UDID='iphone-udid'/);
  assert.match(result.stdout, /WHIM_WATCH_SIMULATOR_UDID='watch-udid'/);
  assert.match(await readFile(join(root, 'commands'), 'utf8'), /simctl pair watch-udid iphone-udid/);
});

test('runtime supported-device catalogue overrides a model with matching nominal version bounds', async () => {
  const { selectCompatibleDeviceType } = await import('./select-apple-runtimes.mjs');
  const types = [
    { identifier: 'excluded-model', productFamily: 'iPhone', minRuntimeVersion: 18 * 65536, maxRuntimeVersion: 0xFFFFFFFF },
    { identifier: 'supported-model', productFamily: 'iPhone', minRuntimeVersion: 18 * 65536, maxRuntimeVersion: 0xFFFFFFFF },
  ];
  const selected = { ...runtime('iOS', '27.0'), supportedDeviceTypes: [{ identifier: 'supported-model', productFamily: 'iPhone' }] };
  assert.equal(selectCompatibleDeviceType(types, 'iPhone', selected).identifier, 'supported-model');
  assert.throws(() => selectCompatibleDeviceType(types, 'iPhone', { ...selected, supportedDeviceTypes: [] }), /No compatible/);
});
