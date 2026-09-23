import assert from 'node:assert/strict';
import { mkdtemp, mkdir, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import path from 'node:path';
import test from 'node:test';

import { checkRepository } from './check-test-colocation.mjs';

async function fixture(t, files) {
  const root = await mkdtemp(path.join(tmpdir(), 'whim-colocation-'));
  t.after(() => rm(root, { force: true, recursive: true }));
  await Promise.all(
    Object.entries(files).map(async ([relativePath, contents]) => {
      const absolutePath = path.join(root, relativePath);
      await mkdir(path.dirname(absolutePath), { recursive: true });
      await writeFile(absolutePath, contents);
    }),
  );
  return root;
}

test('accepts adjacent tests and explicit non-overlapping SwiftPM source lists', async (t) => {
  const root = await fixture(t, {
    'src/iphone/timeline/Timeline.ts': '',
    'src/iphone/timeline/Timeline.test.ts': '',
    'packages/WhimCore/Sources/WhimCore/Notes/Note.swift': '',
    'packages/WhimCore/Sources/WhimCore/Notes/Note.test.swift': '',
    'packages/WhimCore/Sources/WhimCore/Notes/Note.integration.test.swift': '',
    'packages/WhimCore/Package.swift': `
      let productionSources = ["Notes/Note.swift"]
      let unitTestSources = ["Notes/Note.test.swift"]
      let integrationTestSources = ["Notes/Note.integration.test.swift"]
    `,
  });

  assert.deepEqual(await checkRepository(root), []);
});

test('rejects tests without adjacent implementations', async (t) => {
  const root = await fixture(t, {
    'src/iphone/timeline/Missing.test.ts': '',
  });

  const errors = await checkRepository(root);
  assert.ok(errors.some((error) => error.includes('Missing.test.ts')));
});

test('rejects generic architecture folders', async (t) => {
  const root = await fixture(t, { 'src/iphone/components/Button.tsx': '' });

  assert.ok((await checkRepository(root)).some((error) => error.includes('components')));
});

test('rejects Swift files missing from or misclassified by Package.swift', async (t) => {
  const root = await fixture(t, {
    'packages/WhimCore/Sources/WhimCore/Notes/Note.swift': '',
    'packages/WhimCore/Sources/WhimCore/Notes/Note.test.swift': '',
    'packages/WhimCore/Package.swift': `
      let productionSources = ["Notes/Note.swift", "Notes/Note.test.swift"]
      let unitTestSources = []
      let integrationTestSources = []
    `,
  });

  const errors = await checkRepository(root);
  assert.ok(errors.some((error) => error.includes('productionSources')));
  assert.ok(errors.some((error) => error.includes('unitTestSources')));
});

test('accepts owned Swift files in their intended Xcode source targets', async (t) => {
  const root = await fixture(t, {
    'src/watch/app-composition/WhimWatchApp.swift': '',
    'src/watch/app-composition/WhimWatchApp.test.swift': '',
    'e2e/watch/WhimWatch.e2e.test.swift': '',
    'ios/whim.xcodeproj/project.pbxproj': `
      PROD_FILE /* WhimWatchApp.swift */ = {isa = PBXFileReference; path = "../src/watch/app-composition/WhimWatchApp.swift"; };
      UNIT_FILE /* WhimWatchApp.test.swift */ = {isa = PBXFileReference; path = "../src/watch/app-composition/WhimWatchApp.test.swift"; };
      E2E_FILE /* WhimWatch.e2e.test.swift */ = {isa = PBXFileReference; path = ../e2e/watch/WhimWatch.e2e.test.swift; };
      PROD_BUILD /* WhimWatchApp.swift in Sources */ = {isa = PBXBuildFile; fileRef = PROD_FILE /* WhimWatchApp.swift */; };
      UNIT_BUILD /* WhimWatchApp.test.swift in Sources */ = {isa = PBXBuildFile; fileRef = UNIT_FILE /* WhimWatchApp.test.swift */; };
      E2E_BUILD /* WhimWatch.e2e.test.swift in Sources */ = {isa = PBXBuildFile; fileRef = E2E_FILE /* WhimWatch.e2e.test.swift */; };
      PROD_PHASE /* Sources */ = {isa = PBXSourcesBuildPhase; files = (PROD_BUILD /* WhimWatchApp.swift in Sources */,); };
      UNIT_PHASE /* Sources */ = {isa = PBXSourcesBuildPhase; files = (UNIT_BUILD /* WhimWatchApp.test.swift in Sources */,); };
      E2E_PHASE /* Sources */ = {isa = PBXSourcesBuildPhase; files = (E2E_BUILD /* WhimWatch.e2e.test.swift in Sources */,); };
      PROD_TARGET /* WhimWatch */ = {isa = PBXNativeTarget; buildPhases = (PROD_PHASE /* Sources */,); name = WhimWatch; };
      UNIT_TARGET /* WhimWatchTests */ = {isa = PBXNativeTarget; buildPhases = (UNIT_PHASE /* Sources */,); name = WhimWatchTests; };
      E2E_TARGET /* WhimWatchUITests */ = {isa = PBXNativeTarget; buildPhases = (E2E_PHASE /* Sources */,); name = WhimWatchUITests; };
    `,
  });

  assert.deepEqual(await checkRepository(root), []);
});

test('rejects Xcode tests in production targets and missing intended production membership', async (t) => {
  const root = await fixture(t, {
    'src/watch/app-composition/WhimWatchApp.swift': '',
    'src/watch/app-composition/WhimWatchApp.test.swift': '',
    'ios/whim.xcodeproj/project.pbxproj': `
      PROD_FILE /* WhimWatchApp.swift */ = {isa = PBXFileReference; path = "../src/watch/app-composition/WhimWatchApp.swift"; };
      UNIT_FILE /* WhimWatchApp.test.swift */ = {isa = PBXFileReference; path = "../src/watch/app-composition/WhimWatchApp.test.swift"; };
      UNIT_BUILD /* WhimWatchApp.test.swift in Sources */ = {isa = PBXBuildFile; fileRef = UNIT_FILE /* WhimWatchApp.test.swift */; };
      PROD_PHASE /* Sources */ = {isa = PBXSourcesBuildPhase; files = (UNIT_BUILD /* WhimWatchApp.test.swift in Sources */,); };
      PROD_TARGET /* WhimWatch */ = {isa = PBXNativeTarget; buildPhases = (PROD_PHASE /* Sources */,); name = WhimWatch; };
    `,
  });

  const errors = await checkRepository(root);
  assert.ok(errors.some((error) => error.includes('WhimWatchApp.test.swift: must not compile in WhimWatch')));
  assert.ok(errors.some((error) => error.includes('WhimWatchApp.swift: missing from WhimWatch')));
});

test('rejects native iPhone tests omitted from the presentation package', async (t) => {
  const root = await fixture(t, {
    'src/iphone/timeline/TimelineFormat.swift': '',
    'src/iphone/timeline/TimelineFormat.test.swift': '',
    'Package.swift': 'let modelSources = ["timeline/TimelineFormat.swift"]\nlet unitSources = []\nlet integrationSources = []',
  });
  assert.ok((await checkRepository(root)).some(error => error.includes('TimelineFormat.test.swift') && error.includes('unitSources')));
});

test('rejects system-surface tests missing their dedicated target', async (t) => {
  const root = await fixture(t, {
    'src/intents/recording/RecordWhimIntent.swift': '',
    'src/intents/recording/RecordWhimIntent.test.swift': '',
    'ios/whim.xcodeproj/project.pbxproj': '/* system targets */',
  });
  assert.ok((await checkRepository(root)).some(error => error.includes('RecordWhimIntent.test.swift: missing from WhimSystemSurfaceTests')));
});

test('rejects dangling Xcode package products before a clean extension build', async (t) => {
  const project = `
    TARGET /* WhimComplication */ = {isa = PBXNativeTarget; name = WhimComplication; packageProductDependencies = (CORE /* WhimCore */,); };
    BUILD /* WhimCore in Frameworks */ = {isa = PBXBuildFile; productRef = CORE /* WhimCore */; };
    PACKAGE /* WhimCore */ = {isa = XCLocalSwiftPackageReference; relativePath = ../packages/WhimCore; };
  `;
  const root = await fixture(t, { 'ios/whim.xcodeproj/project.pbxproj': project });
  const errors = await checkRepository(root);
  assert.ok(errors.some(error => error.includes('WhimComplication') && error.includes('CORE')));
  assert.ok(errors.some(error => error.includes('BUILD') && error.includes('CORE')));
  await writeFile(path.join(root, 'ios/whim.xcodeproj/project.pbxproj'), project + `
    CORE /* WhimCore */ = {isa = XCSwiftPackageProductDependency; package = PACKAGE /* WhimCore */; productName = WhimCore; };
  `);
  assert.deepEqual(await checkRepository(root), []);
});
