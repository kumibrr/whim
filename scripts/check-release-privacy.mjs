import { readdir, readFile } from 'node:fs/promises';
import { execFileSync } from 'node:child_process';
import { join, resolve } from 'node:path';
import { pathToFileURL } from 'node:url';

const excluded = new Set(['.build', 'build', 'node_modules', 'Pods', '.git']);
const disallowed = /\bimport\s+(?:Sentry|FirebaseAnalytics|FirebaseCrashlytics|AmplitudeSwift|Amplitude|Mixpanel|Segment|Analytics)\b|@sentry\/|mixpanel-swift|amplitude-swift|analytics-swift|sentry-cocoa|@segment\/analytics|firebase\/analytics|["'](?:sentry|mixpanel|amplitude|analytics-node|@amplitude\/[^"']*)["']/i;
async function files(root, relative) {
  let entries;
  try { entries = await readdir(join(root, relative), { withFileTypes: true }); }
  catch (error) { if (error.code === 'ENOENT') return []; throw error; }
  const result = [];
  for (const entry of entries) {
    const path = join(relative, entry.name);
    if (entry.isDirectory() && !excluded.has(entry.name)) result.push(...await files(root, path));
    else if (entry.isFile() && /\.(?:swift|[cm]?[jt]s|json|resolved|pbxproj|plist)$/.test(entry.name) && !entry.name.includes('.test.')) result.push(path);
  }
  return result;
}
export async function checkReleasePrivacy(root = process.cwd(), app) {
  const errors = [];
  const paths = ['package.json', 'package-lock.json', ...await files(root, 'src'), ...await files(root, 'packages'), ...await files(root, 'ios')];
  for (const path of paths) {
    let source;
    try { source = await readFile(join(root, path), 'utf8'); }
    catch (error) { if (error.code === 'ENOENT') continue; throw error; }
    if (disallowed.test(source)) errors.push(`${path}: disallowed tracking/diagnostics SDK reference`);
  }
  const manifests = [join(root, 'ios/whim/PrivacyInfo.xcprivacy')];
  if (app) for (const bundle of ['', 'PlugIns/WhimLiveActivity.appex', 'Watch/WhimWatch.app', 'Watch/WhimWatch.app/PlugIns/WhimComplication.appex']) {
    manifests.push(join(app, bundle, 'PrivacyInfo.xcprivacy'));
  }
  for (const path of manifests) {
    try {
      const manifest = JSON.parse(execFileSync('python3', ['-c',
        'import json,plistlib,sys; print(json.dumps(plistlib.load(open(sys.argv[1], "rb"))))',
        path], { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] }));
      if (manifest.NSPrivacyTracking !== false || (manifest.NSPrivacyTrackingDomains ?? []).length) errors.push(`${path}: tracking must be disabled`);
      if (!Array.isArray(manifest.NSPrivacyCollectedDataTypes) || manifest.NSPrivacyCollectedDataTypes.length) errors.push(`${path}: unexpected app-operator data collection`);
      const reasons = new Map((manifest.NSPrivacyAccessedAPITypes ?? []).map(item => [item.NSPrivacyAccessedAPIType, item.NSPrivacyAccessedAPITypeReasons]));
      for (const [category, required] of Object.entries({
        UserDefaults: ['CA92.1', '1C8F.1'], FileTimestamp: ['C617.1'], SystemBootTime: ['35F9.1'],
      })) {
        for (const reason of required) if (!reasons.get(`NSPrivacyAccessedAPICategory${category}`)?.includes(reason)) errors.push(`${path}: missing ${category} reason ${reason}`);
      }
    } catch { errors.push(`${path}: missing or invalid plist`); }
  }
  return errors;
}
if (process.argv[1] && import.meta.url === pathToFileURL(resolve(process.argv[1])).href) {
  const errors = await checkReleasePrivacy(process.argv[2] ?? process.cwd(), process.argv[3]);
  if (errors.length) { console.error(errors.join('\n')); process.exitCode = 1; }
  else console.log('Release privacy source and manifest checks passed.');
}
