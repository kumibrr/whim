import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { mkdtemp, mkdir, writeFile, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { test } from 'node:test';
import { checkReleasePrivacy } from './check-release-privacy.mjs';

const manifest = `<?xml version="1.0"?><plist version="1.0"><dict>
<key>NSPrivacyTracking</key><false/><key>NSPrivacyCollectedDataTypes</key><array/>
<key>NSPrivacyAccessedAPITypes</key><array>
<dict><key>NSPrivacyAccessedAPIType</key><string>NSPrivacyAccessedAPICategoryUserDefaults</string><key>NSPrivacyAccessedAPITypeReasons</key><array><string>CA92.1</string><string>1C8F.1</string></array></dict>
<dict><key>NSPrivacyAccessedAPIType</key><string>NSPrivacyAccessedAPICategoryFileTimestamp</string><key>NSPrivacyAccessedAPITypeReasons</key><array><string>C617.1</string></array></dict>
<dict><key>NSPrivacyAccessedAPIType</key><string>NSPrivacyAccessedAPICategorySystemBootTime</string><key>NSPrivacyAccessedAPITypeReasons</key><array><string>35F9.1</string></array></dict>
</array></dict></plist>`;

test('privacy gate rejects tracking SDK imports and missing App Group reason', async () => {
  const root = await mkdtemp(join(tmpdir(), 'whim-privacy-'));
  try {
    await mkdir(join(root, 'ios/whim'), { recursive: true });
    await mkdir(join(root, 'src'), { recursive: true });
    const path = join(root, 'ios/whim/PrivacyInfo.xcprivacy');
    await writeFile(path, manifest);
    await writeFile(join(root, 'src/App.swift'), 'let amplitude = 0.5\n');
    assert.deepEqual(await checkReleasePrivacy(root), []);
    for (const source of ['import Sentry\n', 'import Mixpanel\nMixpanel.initialize(token: \"fixture\")', 'import Segment\n', 'import Amplitude\n']) {
      await writeFile(join(root, 'src/App.swift'), source);
      assert.ok((await checkReleasePrivacy(root)).some(error => error.includes('src/App.swift')), source);
    }
    await writeFile(join(root, 'src/App.swift'), 'let amplitude = 0.5\n');
    await writeFile(path, manifest.replace('<string>1C8F.1</string>', ''));
    assert.ok((await checkReleasePrivacy(root)).some(error => error.includes('1C8F.1')));
    await writeFile(path, manifest.replace('<false/>', '<true/>'));
    assert.ok((await checkReleasePrivacy(root)).some(error => error.includes('tracking')));
  } finally { await rm(root, { recursive: true, force: true }); }
});


test('release privacy gate inspects every embedded target, including missing and invalid manifests', async () => {
  const root = await mkdtemp(join(tmpdir(), 'whim-archive-privacy-'));
  const app = join(root, 'archive/Products/Applications/whim.app');
  const bundles = ['', 'PlugIns/WhimLiveActivity.appex', 'Watch/WhimWatch.app', 'Watch/WhimWatch.app/PlugIns/WhimComplication.appex'];
  try {
    await mkdir(join(root, 'ios/whim'), { recursive: true });
    await writeFile(join(root, 'ios/whim/PrivacyInfo.xcprivacy'), manifest);
    for (const bundle of bundles) {
      await mkdir(join(app, bundle), { recursive: true });
      await writeFile(join(app, bundle, 'PrivacyInfo.xcprivacy'), manifest);
    }
    assert.deepEqual(await checkReleasePrivacy(root, app), []);
    for (const bundle of bundles) {
      const path = join(app, bundle, 'PrivacyInfo.xcprivacy');
      await rm(path);
      assert.ok((await checkReleasePrivacy(root, app)).some(error => error.includes(path)), `Missing manifest: ${bundle}`);
      await writeFile(path, manifest.replace('<false/>', '<true/>'));
      assert.ok((await checkReleasePrivacy(root, app)).some(error => error.includes(path) && error.includes('tracking')));
      await writeFile(path, manifest.replace('<string>1C8F.1</string>', ''));
      assert.ok((await checkReleasePrivacy(root, app)).some(error => error.includes(path) && error.includes('1C8F.1')));
      await writeFile(path, manifest);
    }
  } finally { await rm(root, { recursive: true, force: true }); }
});


test('privacy shell entry point fails for an archive missing bundled manifests', async () => {
  const app = await mkdtemp(join(tmpdir(), 'whim-missing-manifests-'));
  try {
    const result = spawnSync('bash', ['scripts/check-release-privacy.sh', app], { encoding: 'utf8' });
    assert.equal(result.status, 1);
    assert.ok(result.stderr.includes(join(app, 'PrivacyInfo.xcprivacy')));
  } finally { await rm(app, { recursive: true, force: true }); }
});
