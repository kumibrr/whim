import { spawnSync } from 'node:child_process';
import { cp, mkdir, mkdtemp, readFile, rm, symlink, writeFile } from 'node:fs/promises';
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
  const app = JSON.parse(await readFile(join(root, 'ios/package.json'), 'utf8'));
  await writeFile(join(root, 'ios/package.json'), JSON.stringify({ ...app, version: '1.0.0' }, null, 2) + '\n');
  const lock = JSON.parse(await readFile(join(root, 'package-lock.json'), 'utf8'));
  lock.packages.ios.version = '1.0.0';
  await writeFile(join(root, 'package-lock.json'), JSON.stringify(lock, null, 2) + '\n');
  const projectPath = join(root, 'ios/whim.xcodeproj/project.pbxproj');
  await writeFile(projectPath, (await readFile(projectPath, 'utf8')).replace(/MARKETING_VERSION = [^;]+;/g, 'MARKETING_VERSION = 1.0.0;'));
  await symlink(join(repository, 'node_modules'), join(root, 'node_modules'));
  await writeFile(join(root, '.changeset/release-fixture.md'), '---\n"@whim/app": patch\n---\n\nRecover Watch recordings.\n');
  command(root, 'git', ['init', '-b', 'main']);
  return root;
}

export function command(root, executable, args, options = {}) {
  const result = spawnSync(executable, args, { cwd: root, encoding: 'utf8', env: { ...process.env, npm_config_offline: 'true', ...options.env } });
  if (result.status !== 0) throw new Error(`${executable} ${args.join(' ')}: ${result.stderr}\n${result.stdout}`);
  return result.stdout;
}


export async function releaseFixture(t) {
  const root = await versionFixture(t);
  const remote = `${root}-remote.git`;
  t.after(() => rm(remote, { recursive: true, force: true }));
  command(root, 'git', ['config', 'user.email', 'release-fixture@example.invalid']);
  command(root, 'git', ['config', 'user.name', 'Release fixture']);
  await writeFile(join(root, '.gitignore'), 'node_modules\n');
  command(root, 'git', ['add', '.']);
  command(root, 'git', ['commit', '-m', 'Fixture app with a pending Changeset']);
  command(root, 'git', ['init', '--bare', '--initial-branch=main', remote]);
  command(root, 'git', ['remote', 'add', 'origin', remote]);
  command(root, 'git', ['push', 'origin', 'main']);
  command(root, 'git', ['switch', '-c', 'release-fixture']);
  const initial = command(root, 'git', ['rev-parse', 'HEAD']).trim();
  return { root, remote, initial };
}
