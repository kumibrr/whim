import { join, resolve } from 'node:path';
import { pathToFileURL } from 'node:url';
import { runCommand } from './prepare-release-version.mjs';
import { verifyCloudRelease } from './prepare-cloud-release.mjs';

export async function cloudPhase(phase, root = process.cwd(), { env = process.env, run = runCommand } = {}) {
  const execute = (exe, args) => run(exe, args, { cwd: root });
  if ((env.CI_WORKFLOW === 'Release' || env.CI_WORKFLOW_ID === '62dc6f87-fa57-4e9e-810a-43aa1dd13728') && !env.CI_BRANCH?.startsWith('release-build/')) throw Error('Release requires a prepared release-build/<tag> branch.');
  if (phase === 'clone') {
    if (env.CI_TAG) throw Error('Tag-triggered Cloud builds are disabled. Build the prepared release-build/<tag> branch.');
    if (env.CI_BRANCH?.startsWith('release-build/')) await verifyCloudRelease(root, env.CI_BRANCH, { run });
    return;
  }
  const action = env.CI_XCODEBUILD_ACTION;
  if (!['archive', 'build', 'analyze', 'build-for-testing', 'test-without-building'].includes(action)) throw Error(`Unknown Cloud action: ${action}`);
  // Keep one native Archive action for releases, or Build for PR CI. Never silently omit gates.
  if (!['archive', 'build'].includes(action)) throw Error(`Unsupported Cloud action ${action}; configure Archive (release) or Build (PR CI).`);
  if (phase === 'pre') {
    if (env.CI_BRANCH?.startsWith('release-build/')) await verifyCloudRelease(root, env.CI_BRANCH, { run });
    await execute('npm', ['ci', '--no-audit', '--no-fund']);
    await execute('bash', ['scripts/check-release-privacy.sh']);
    await execute('bash', ['scripts/check-release-metadata.sh']);
    await execute('npm', ['run', 'test:all']);
    if (action === 'build') await execute('npm', ['run', 'verify:release']);
    return;
  }
  if (phase !== 'post') throw Error(`Unknown Cloud hook: ${phase}`);
  if (env.CI_XCODEBUILD_EXIT_CODE !== '0') throw Error(`Native Xcode Cloud action failed (${env.CI_XCODEBUILD_EXIT_CODE ?? 'missing exit code'}).`);
  if (action === 'archive') {
    if (!env.CI_ARCHIVE_PATH) throw Error('Missing native Cloud archive path.');
    const app = join(env.CI_ARCHIVE_PATH, 'Products/Applications/whim.app');
    for (const gate of ['fixtures', 'privacy', 'metadata']) await execute('bash', [`scripts/check-release-${gate}.sh`, app]);
  }
}

if (process.argv[1] && import.meta.url === pathToFileURL(resolve(process.argv[1])).href) {
  try { await cloudPhase(process.argv[2], process.env.CI_PRIMARY_REPOSITORY_PATH); }
  catch (error) { console.error(error.message); process.exitCode = 1; }
}
