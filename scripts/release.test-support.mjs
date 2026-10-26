import { spawnSync } from 'node:child_process';
import { cp, mkdir, mkdtemp, rm, symlink, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';

const repository = fileURLToPath(new URL('..', import.meta.url));

// Real Changesets, npm, and owned version modules; no network or Apple tools.
export async function versionFixture(t) {
  const root = await mkdtemp(join(tmpdir(), 'whim-version-'));
  t.after(() => rm(root, { recursive: true, force: true }));
  for (const path of ['package.json', 'package-lock.json', 'ios/package.json', 'ios/whim.xcodeproj/project.pbxproj', '.changeset/config.json', 'scripts/sync-app-version.mjs', 'scripts/check-release-metadata.mjs', 'scripts/prepare-release-version.mjs']) {
    await mkdir(join(root, path, '..'), { recursive: true });
    try { await cp(join(repository, path), join(root, path)); }
    catch (error) { if (error.code !== 'ENOENT') throw error; }
  }
  await symlink(join(repository, 'node_modules'), join(root, 'node_modules'));
  await writeFile(join(root, '.changeset/release-fixture.md'), '---\n"@whim/app": patch\n---\n\nRecover Watch recordings.\n');
  command(root, 'git', ['init', '-b', 'main']);
  return root;
}

export function command(root, executable, args) {
  const result = spawnSync(executable, args, { cwd: root, encoding: 'utf8', env: { ...process.env, npm_config_offline: 'true' } });
  if (result.status !== 0) throw new Error(`${executable} ${args.join(' ')}: ${result.stderr}\n${result.stdout}`);
  return result.stdout;
}

