import { readFile } from 'node:fs/promises';
import { execFileSync } from 'node:child_process';
import { join, resolve } from 'node:path';
import { pathToFileURL } from 'node:url';

const displayName = 'whim';
const bundles = ['', 'PlugIns/WhimLiveActivity.appex', 'Watch/WhimWatch.app', 'Watch/WhimWatch.app/PlugIns/WhimComplication.appex'];

function plist(path) {
  return JSON.parse(execFileSync('python3', ['-c',
    'import json,plistlib,sys; print(json.dumps(plistlib.load(open(sys.argv[1], "rb"))))',
    path], { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] }));
}

// ios/package.json is the Changesets-managed source of the App Store marketing version.
export async function appVersion(root) {
  return JSON.parse(await readFile(join(root, 'ios/package.json'), 'utf8')).version;
}

function checkSubmissionKeys(path, info, errors) {
  if (info.ITSAppUsesNonExemptEncryption !== false) errors.push(`${path}: ITSAppUsesNonExemptEncryption must be false`);
  if ('LSMinimumSystemVersion' in info) errors.push(`${path}: LSMinimumSystemVersion is a macOS key`);
}

export async function checkReleaseMetadata(root = process.cwd(), app) {
  const errors = [];
  const version = await appVersion(root);
  const infoPath = join(root, 'ios/whim/Info.plist');
  const info = plist(infoPath);
  if (info.CFBundleShortVersionString !== '$(MARKETING_VERSION)') errors.push(`${infoPath}: CFBundleShortVersionString must be $(MARKETING_VERSION)`);
  if (info.CFBundleVersion !== '$(CURRENT_PROJECT_VERSION)') errors.push(`${infoPath}: CFBundleVersion must be $(CURRENT_PROJECT_VERSION)`);
  if (info.CFBundleDisplayName !== displayName) errors.push(`${infoPath}: CFBundleDisplayName must be ${displayName}`);
  checkSubmissionKeys(infoPath, info, errors);

  const projectPath = join(root, 'ios/whim.xcodeproj/project.pbxproj');
  const project = await readFile(projectPath, 'utf8');
  const versions = [...project.matchAll(/MARKETING_VERSION = ([^;]+);/g)].map(match => match[1]);
  if (!versions.length || versions.some(value => value !== version)) errors.push(`${projectPath}: every MARKETING_VERSION must be ${version}; run node scripts/sync-app-version.mjs`);
  for (const [, name] of project.matchAll(/INFOPLIST_KEY_CFBundleDisplayName = ([^;]+);/g)) {
    if (name !== displayName) errors.push(`${projectPath}: INFOPLIST_KEY_CFBundleDisplayName must be ${displayName}`);
  }

  if (app) {
    let build;
    for (const bundle of bundles) {
      const path = join(app, bundle, 'Info.plist');
      let built;
      try { built = plist(path); } catch { errors.push(`${path}: missing or invalid plist`); continue; }
      if (built.CFBundleShortVersionString !== version) errors.push(`${path}: CFBundleShortVersionString must be ${version}`);
      build ??= built.CFBundleVersion;
      if (!built.CFBundleVersion || built.CFBundleVersion !== build) errors.push(`${path}: CFBundleVersion must match the iPhone app`);
      if (built.CFBundleDisplayName !== displayName) errors.push(`${path}: CFBundleDisplayName must be ${displayName}`);
      if (bundle === '') checkSubmissionKeys(path, built, errors);
    }
  }
  return errors;
}

if (process.argv[1] && import.meta.url === pathToFileURL(resolve(process.argv[1])).href) {
  const errors = await checkReleaseMetadata(process.argv[2] ?? process.cwd(), process.argv[3]);
  if (errors.length) { console.error(errors.join('\n')); process.exitCode = 1; }
  else console.log('Release metadata checks passed.');
}
