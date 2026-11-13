import { randomUUID } from 'node:crypto';
import { mkdir, writeFile } from 'node:fs/promises';
import { dirname, resolve } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { ensureFullHistory, freezeSnapshot, shaPattern } from './benchmark-history.mjs';
import { runCommand } from './prepare-release-version.mjs';

export function sourceContext(env, sha) {
  if (!env.CI_XCODE_CLOUD && env.CI !== 'TRUE') return 'local';
  const match = /^benchmark-input\/(main|pr\/[1-9]\d*)\/([a-f0-9]{40})$/.exec(env.CI_BRANCH ?? '');
  if (!match || match[2] !== sha || env.CI_COMMIT !== sha) throw Error('Benchmark input ref must identify the exact source commit/context.');
  return match[1];
}

export async function prepareNativeInput(root, output, { env = process.env, run = runCommand } = {}) {
  const execute = async (exe, args) => (await run(exe, args, { cwd: root, capture: true })).trim();
  const sha = await execute('git', ['rev-parse', 'HEAD']);
  if (!shaPattern.test(sha)) throw Error('Invalid measured source SHA.');
  const context = sourceContext(env, sha);
  let historyRef = env.WHIM_BENCHMARK_HISTORY_REF ?? 'HEAD';
  if (context !== 'local') {
    await ensureFullHistory(root, { run });
    await execute('git', ['fetch', '--no-tags', 'origin', 'main']);
    historyRef = await execute('git', ['rev-parse', 'FETCH_HEAD']);
  }
  const frozen = await freezeSnapshot(root, sha, historyRef, { run });
  const xcode = (await execute('xcodebuild', ['-version'])).replaceAll('\n', ' ');
  const value = { schemaVersion: 1, protocol: frozen.policy.protocol, fixture: frozen.policy.fixture,
    policy: frozen.policy, frozen,
    source: { sha, parents: (await execute('git', ['show', '-s', '--format=%P', sha])).split(' ').filter(Boolean),
      context, committedAt: await execute('git', ['show', '-s', '--format=%cI', sha]) },
    run: { id: env.CI_BUILD_ID ?? randomUUID(), number: Number(env.CI_BUILD_NUMBER ?? 0),
      url: env.CI_BUILD_URL ?? 'local', measuredAt: new Date().toISOString() },
    environment: { architecture: process.arch, cpu: 'pending', macOS: await execute('sw_vers', ['-productVersion']),
      kernel: 'pending', xcode, runtime: 'pending', device: 'pending', configuration: frozen.policy.configuration } };
  const text = JSON.stringify(value);
  if (Buffer.byteLength(text) > 4 * 1024 * 1024) throw Error('Benchmark baseline input exceeds the native resource bound.');
  await mkdir(dirname(output), { recursive: true });
  await writeFile(output, text + '\n');
  return value;
}

if (process.argv[1] && import.meta.url === pathToFileURL(resolve(process.argv[1])).href) {
  try {
    if (!process.argv[2]) throw Error('Usage: node scripts/benchmark-input.mjs <test-bundle-resource-path>');
    const root = fileURLToPath(new URL('..', import.meta.url));
    await prepareNativeInput(root, process.argv[2]);
  } catch (error) { console.error(error.message); process.exitCode = 1; }
}
