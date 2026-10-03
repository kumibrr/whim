import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { cp, mkdtemp, mkdir, readFile, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { test } from 'node:test';
import { checkReleaseMetadata } from './check-release-metadata.mjs';
import { syncAppVersion } from './sync-app-version.mjs';

const repository = new URL('..', import.meta.url).pathname;
const bundles = ['', 'PlugIns/WhimLiveActivity.appex', 'Watch/WhimWatch.app', 'Watch/WhimWatch.app/PlugIns/WhimComplication.appex'];

function plist(entries) {
  const values = Object.entries(entries).map(([key, value]) => `<key>${key}</key>${typeof value === 'boolean' ? `<${value}/>` : `<string>${value}</string>`}`);
  return `<?xml version="1.0"?><plist version="1.0"><dict>${values.join('')}</dict></plist>`;
}

async function sourceFixture() {
  const root = await mkdtemp(join(tmpdir(), 'whim-metadata-'));
  for (const path of ['ios/package.json', 'ios/whim/Info.plist', 'ios/whim.xcodeproj/project.pbxproj']) {
    await mkdir(join(root, path, '..'), { recursive: true });
    await cp(join(repository, path), join(root, path));
  }
  return root;
}

async function builtApp(root, overrides = {}) {
  const app = join(root, 'Whim.xcarchive/Products/Applications/whim.app');
  for (const bundle of bundles) {
    await mkdir(join(app, bundle), { recursive: true });
    await writeFile(join(app, bundle, 'Info.plist'), plist({
      CFBundleDisplayName: 'whim', CFBundleShortVersionString: '1.0.0', CFBundleVersion: '1',
      ...(bundle === '' ? { ITSAppUsesNonExemptEncryption: false } : {}),
      ...overrides[bundle],
    }));
  }
  return app;
}

test('repository release metadata is consistent', async () => {
  assert.deepEqual(await checkReleaseMetadata(repository), []);
});

test('metadata gate rejects source plist and project drift', async () => {
  const root = await sourceFixture();
  const infoPath = join(root, 'ios/whim/Info.plist');
  const projectPath = join(root, 'ios/whim.xcodeproj/project.pbxproj');
  try {
    const info = await readFile(infoPath, 'utf8');
    const project = await readFile(projectPath, 'utf8');
    for (const [label, broken, expected] of [
      ['hard-coded version', info.replace('$(MARKETING_VERSION)', '1.0.0'), 'CFBundleShortVersionString'],
      ['hard-coded build', info.replace('$(CURRENT_PROJECT_VERSION)', '1'), 'CFBundleVersion'],
      ['encryption', info.replace(/<key>ITSAppUsesNonExemptEncryption<\/key>\s*<false\/>/, ''), 'ITSAppUsesNonExemptEncryption'],
      ['macOS key', info.replace('<key>LSRequiresIPhoneOS</key>', '<key>LSMinimumSystemVersion</key><string>12.0</string><key>LSRequiresIPhoneOS</key>'), 'LSMinimumSystemVersion'],
      ['display name', info.replace('<string>whim</string>', '<string>Whim</string>'), 'CFBundleDisplayName'],
    ]) {
      await writeFile(infoPath, broken);
      assert.ok((await checkReleaseMetadata(root)).some(error => error.includes(expected)), label);
    }
    await writeFile(infoPath, info);
    await writeFile(projectPath, project.replace('MARKETING_VERSION = 1.0.0;', 'MARKETING_VERSION = 0.9.0;'));
    assert.ok((await checkReleaseMetadata(root)).some(error => error.includes('MARKETING_VERSION')));
    await writeFile(projectPath, project.replace('INFOPLIST_KEY_CFBundleDisplayName = whim;', 'INFOPLIST_KEY_CFBundleDisplayName = Whim;'));
    assert.ok((await checkReleaseMetadata(root)).some(error => error.includes('CFBundleDisplayName')));
  } finally { await rm(root, { recursive: true, force: true }); }
});

test('metadata gate inspects every embedded bundle of a built app', async () => {
  const root = await sourceFixture();
  try {
    assert.deepEqual(await checkReleaseMetadata(root, await builtApp(root)), []);
    for (const [bundle, override, expected] of [
      ['Watch/WhimWatch.app', { CFBundleShortVersionString: '1.0.1' }, 'CFBundleShortVersionString'],
      ['PlugIns/WhimLiveActivity.appex', { CFBundleVersion: '2' }, 'CFBundleVersion'],
      ['Watch/WhimWatch.app/PlugIns/WhimComplication.appex', { CFBundleDisplayName: 'Whim' }, 'CFBundleDisplayName'],
      ['', { ITSAppUsesNonExemptEncryption: true }, 'ITSAppUsesNonExemptEncryption'],
      ['', { LSMinimumSystemVersion: '12.0' }, 'LSMinimumSystemVersion'],
    ]) {
      await rm(join(root, 'Whim.xcarchive'), { recursive: true });
      const app = await builtApp(root, { [bundle]: override });
      assert.ok((await checkReleaseMetadata(root, app)).some(error => error.includes(join(app, bundle, 'Info.plist')) && error.includes(expected)), `${bundle}: ${expected}`);
    }
  } finally { await rm(root, { recursive: true, force: true }); }
});

test('version sync propagates the Changesets app version to every Xcode target', async () => {
  const root = await sourceFixture();
  try {
    const manifestPath = join(root, 'ios/package.json');
    const manifest = JSON.parse(await readFile(manifestPath, 'utf8'));
    await writeFile(manifestPath, JSON.stringify({ ...manifest, version: '1.1.0' }, null, 2) + '\n');
    assert.ok((await checkReleaseMetadata(root)).some(error => error.includes('MARKETING_VERSION')));
    await syncAppVersion(root);
    assert.deepEqual(await checkReleaseMetadata(root), []);
    const project = await readFile(join(root, 'ios/whim.xcodeproj/project.pbxproj'), 'utf8');
    assert.ok(!project.includes('MARKETING_VERSION = 1.0.0;'));
    assert.ok(project.includes('MARKETING_VERSION = 1.1.0;'));
  } finally { await rm(root, { recursive: true, force: true }); }
});

test('metadata shell entry point fails for a built app with a stale version', async () => {
  const root = await sourceFixture();
  try {
    const app = await builtApp(root, { 'Watch/WhimWatch.app': { CFBundleShortVersionString: '0.9.0' } });
    const result = spawnSync('bash', [join(repository, 'scripts/check-release-metadata.sh'), app], { encoding: 'utf8' });
    assert.equal(result.status, 1);
    assert.ok(result.stderr.includes('CFBundleShortVersionString'));
  } finally { await rm(root, { recursive: true, force: true }); }
});
