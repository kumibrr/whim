import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { join } from 'node:path';
import { test } from 'node:test';
import { prepareReleaseVersion, runCommand } from './prepare-release-version.mjs';
import { command, versionFixture } from './release.test-support.mjs';

test('release:version consumes Changesets and keeps Xcode and the workspace lockfile consistent', async t => {
  const root = await versionFixture(t);
  const before = JSON.parse(await readFile(join(root, 'ios/package.json'), 'utf8')).version;
  const [major, minor, patch] = before.split('.').map(Number);
  const expected = `${major}.${minor}.${patch + 1}`;
  command(root, 'npm', ['run', 'release:version']);
  const manifest = JSON.parse(await readFile(join(root, 'ios/package.json'), 'utf8'));
  const lock = JSON.parse(await readFile(join(root, 'package-lock.json'), 'utf8'));
  assert.equal(manifest.version, expected);
  assert.equal(lock.packages.ios.version, expected);
  const project = await readFile(join(root, 'ios/whim.xcodeproj/project.pbxproj'), 'utf8');
  const versions = [...project.matchAll(/MARKETING_VERSION = ([^;]+);/g)].map(match => match[1]);
  assert.ok(versions.length > 0);
  assert.ok(versions.every(version => version === expected));
  assert.match(await readFile(join(root, 'ios/CHANGELOG.md'), 'utf8'), /Recover Watch recordings\./);
  await assert.rejects(readFile(join(root, '.changeset/release-fixture.md')), { code: 'ENOENT' });
});


test('a failed Changesets command preserves the project and propagates its failure', async t => {
  const root = await versionFixture(t);
  const path = join(root, 'ios/whim.xcodeproj/project.pbxproj');
  const before = await readFile(path, 'utf8');
  await assert.rejects(prepareReleaseVersion(root, async () => { throw new Error('Changesets failed'); }), /Changesets failed/);
  assert.equal(await readFile(path, 'utf8'), before);
});

test('the process boundary rejects a nonzero exit', async () => {
  await assert.rejects(runCommand(process.execPath, ['-e', 'process.exit(7)']), /exit 7/);
});

test('the process boundary passes the isolated index environment to Git', async t => {
  const root = await versionFixture(t);
  const index = join(root, 'isolated-index');
  await runCommand('git', ['add', 'ios/package.json'], { cwd: root, env: { ...process.env, GIT_INDEX_FILE: index } });
  const isolated = await runCommand('git', ['ls-files'], { cwd: root, capture: true, env: { ...process.env, GIT_INDEX_FILE: index } });
  const regular = await runCommand('git', ['ls-files'], { cwd: root, capture: true });
  assert.equal(isolated.trim(), 'ios/package.json');
  assert.equal(regular, '');
});
