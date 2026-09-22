import assert from 'node:assert/strict';
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
