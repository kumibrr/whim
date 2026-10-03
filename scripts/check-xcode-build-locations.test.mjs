import assert from 'node:assert/strict';
import { mkdtemp, mkdir, writeFile, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { test } from 'node:test';
import { checkXcodeBuildLocations } from './check-xcode-build-locations.mjs';

async function put(root, path, contents) { await mkdir(dirname(join(root, path)), { recursive: true }); await writeFile(join(root, path), contents); }

test('build and test invocations must pin products under the script-owned DerivedData', async () => {
  const root = await mkdtemp(join(tmpdir(), 'whim-build-locations-'));
  try {
    await put(root, 'scripts/pinned.sh', 'xcodebuild test -quiet \\\n  -scheme Whim \\\n  "${whim_xcode_build_locations[@]}" \\\n  -destination "id=1"\n');
    await put(root, 'scripts/archive.sh', 'xcodebuild clean archive -archivePath "$archive"\n');
    assert.deepEqual(await checkXcodeBuildLocations(root), []);
    // Xcode's Custom build location preference relocates Build/ even when -derivedDataPath is given.
    await put(root, 'scripts/unpinned.sh', 'xcodebuild build -quiet \\\n  -scheme Whim \\\n  -derivedDataPath "$whim_derived_data"\n');
    assert.ok((await checkXcodeBuildLocations(root)).some(error => error.includes('scripts/unpinned.sh:1')));
  } finally { await rm(root, { recursive: true, force: true }); }
});

test('repository scripts pin every build location', async () => {
  assert.deepEqual(await checkXcodeBuildLocations(join(dirname(fileURLToPath(import.meta.url)), '..')), []);
});
