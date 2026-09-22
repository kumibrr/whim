import assert from 'node:assert/strict';
import { mkdtemp, mkdir, writeFile, rm } from 'node:fs/promises';
import { join, dirname } from 'node:path';
import { tmpdir } from 'node:os';
import { test } from 'node:test';
import { checkReleaseFixtures } from './check-release-fixtures.mjs';

const asset = 'src/iphone/webhook-configuration/configuration-test.m4a';
const bundled = 'packages/WhimCore/Sources/WhimCore/WebhookConfiguration/Fixtures/configuration-test-fixture.m4a';
const binaries = ['whim', 'Watch/WhimWatch.app/WhimWatch', 'PlugIns/WhimLiveActivity.appex/WhimLiveActivity', 'Watch/WhimWatch.app/PlugIns/WhimComplication.appex/WhimComplication'];
async function put(root, path, bytes) { await mkdir(dirname(join(root, path)), { recursive: true }); await writeFile(join(root, path), bytes); }

test('release gate requires approved runtime audio and rejects fixture injection in every executable', async () => {
  const root = await mkdtemp(join(tmpdir(), 'whim-release-'));
  const app = join(root, 'Release/whim.app');
  try {
    for (const binary of binaries) await put(app, binary, 'production executable');
    assert.ok((await checkReleaseFixtures(root, app)).some(error => error.includes('product-owner')));
    await put(root, asset, 'approved fixture');
    await put(root, bundled, 'different fixture');
    assert.ok((await checkReleaseFixtures(root, app)).some(error => error.includes('does not match')));
    await put(root, bundled, 'approved fixture');
    assert.deepEqual(await checkReleaseFixtures(root, app), []);
    for (const binary of binaries) {
      await put(app, binary, 'production\0-WhimFixtureAudio\0');
      assert.ok((await checkReleaseFixtures(root, app)).some(error => error.includes(binary)));
      await put(app, binary, 'production executable');
    }
  } finally { await rm(root, { recursive: true, force: true }); }
});
