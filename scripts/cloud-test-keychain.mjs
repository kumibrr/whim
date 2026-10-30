import { execFile } from 'node:child_process';
import { mkdtemp, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';
import { promisify } from 'node:util';
import { pathToFileURL } from 'node:url';
import { runCommand } from './prepare-release-version.mjs';

const execute = promisify(execFile);
const runSecurity = async args => (await execute('security', args, { encoding: 'utf8' })).stdout;
const paths = output => output.split('\n').map(line => line.trim()).filter(Boolean).map(line => JSON.parse(line));

// This unlocked, empty-password keychain contains synthetic test credentials only.
// Keep Cloud signing keychains searchable, and restore their state before native builds.
export async function withCloudTestKeychain(operation, { security = runSecurity } = {}) {
  const originalSearch = paths(await security(['list-keychains', '-d', 'user']));
  let originalDefault;
  try { [originalDefault] = paths(await security(['default-keychain', '-d', 'user'])); }
  catch (error) {
    if (!/default keychain could not be found|no default keychain|-25307/i.test(error.stderr ?? '')) throw error;
  }
  const directory = await mkdtemp(join(tmpdir(), 'whim-cloud-keychain-'));
  const keychain = join(directory, 'tests.keychain-db');
  let setupStarted = false;
  let result;
  const failures = [];
  try {
    setupStarted = true;
    await security(['create-keychain', '-p', '', keychain]);
    await security(['set-keychain-settings', keychain]);
    await security(['unlock-keychain', '-p', '', keychain]);
    await security(['list-keychains', '-d', 'user', '-s', keychain, ...originalSearch]);
    await security(['default-keychain', '-d', 'user', '-s', keychain]);
    result = await operation();
  } catch (error) { failures.push(error); }
  // Attempt every restoration step even if one fails. A test failure stays visible.
  if (setupStarted) {
    for (const args of [
      ['default-keychain', '-d', 'user', '-s', ...(originalDefault ? [originalDefault] : [])],
      ['list-keychains', '-d', 'user', '-s', ...originalSearch],
      ['delete-keychain', keychain],
    ]) {
      try { await security(args); } catch (error) { failures.push(error); }
    }
  }
  try { await rm(directory, { recursive: true, force: true }); }
  catch (error) { failures.push(error); }
  if (failures.length === 1) throw failures[0];
  if (failures.length) throw new AggregateError(failures, failures.map(error => error.message).join('\n'));
  return result;
}

if (process.argv[1] && import.meta.url === pathToFileURL(resolve(process.argv[1])).href) {
  try {
    const root = process.env.CI_PRIMARY_REPOSITORY_PATH;
    if (!root || process.platform !== 'darwin') throw Error('This keychain wrapper requires the Xcode Cloud macOS action environment.');
    await withCloudTestKeychain(() => runCommand(process.execPath, [join(root, 'scripts/xcode-cloud.mjs'), 'pre'], { cwd: root }));
  } catch (error) { console.error(error.message); process.exitCode = 1; }
}
