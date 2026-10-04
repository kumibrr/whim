import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { chmod, mkdtemp, readFile, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { test } from 'node:test';
import { xcodeBuildLocations } from './xcode-build-locations.mjs';

const helper = new URL('./xcode-build-locations.sh', import.meta.url).pathname;

function settings(products, intermediates) {
  return [
    { action: 'build', target: 'WhimLiveActivity', buildSettings: { BUILD_DIR: '/elsewhere', PROJECT_TEMP_DIR: '/elsewhere' } },
    { action: 'build', target: 'whim', buildSettings: { BUILD_DIR: products, PROJECT_TEMP_DIR: intermediates } },
  ];
}

test('build locations follow the default derived data layout', () => {
  assert.deepEqual(
    xcodeBuildLocations(settings('/repo/ios/build/DerivedData/Build/Products', '/repo/ios/build/DerivedData/Build/Intermediates.noindex/whim.build')),
    { products: '/repo/ios/build/DerivedData/Build/Products', intermediates: '/repo/ios/build/DerivedData/Build/Intermediates.noindex/whim.build' },
  );
});

test('build locations reject settings without the iPhone app target', () => {
  assert.throws(() => xcodeBuildLocations([]), /whim/);
});

test('shell helper resolves custom absolute Xcode build locations outside derived data', async () => {
  const bin = await mkdtemp(join(tmpdir(), 'whim-xcodebuild-'));
  const products = '/Volumes/External SSD/Xcode/Build/Products';
  const intermediates = '/Volumes/External SSD/Xcode/Build/Intermediates.noindex/whim.build';
  try {
    await writeFile(join(bin, 'xcodebuild'), `#!/usr/bin/env bash
printf '%s\\n' "$@" > "${bin}/arguments"
cat <<'JSON'
${JSON.stringify(settings(products, intermediates))}
JSON
`);
    await chmod(join(bin, 'xcodebuild'), 0o755);
    const result = spawnSync('bash', ['-c', `set -euo pipefail
source "$1"
whim_resolve_build_locations "/repo/ios/build/DerivedData" "id=SIMULATOR"
printf '%s\\n%s\\n' "$whim_build_products" "$whim_build_intermediates"`, 'bash', helper], {
      encoding: 'utf8',
      env: { ...process.env, PATH: `${bin}:${process.env.PATH}` },
    });
    assert.equal(result.status, 0, result.stderr);
    assert.equal(result.stdout, `${products}\n${intermediates}\n`);
    const argumentsText = await readFile(join(bin, 'arguments'), 'utf8');
    for (const expected of ['-showBuildSettings', '-json', '-scheme\nWhim', '-derivedDataPath\n/repo/ios/build/DerivedData', '-destination\nid=SIMULATOR', 'SYMROOT=/repo/ios/build/DerivedData/Build/Products', 'OBJROOT=/repo/ios/build/DerivedData/Build/Intermediates.noindex']) {
      assert.ok(argumentsText.includes(expected), expected);
    }
  } finally { await rm(bin, { recursive: true, force: true }); }
});
