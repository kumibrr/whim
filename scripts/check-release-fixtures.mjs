import { readFile } from 'node:fs/promises';
import { join, resolve } from 'node:path';
import { pathToFileURL } from 'node:url';

const executables = ['whim', 'Watch/WhimWatch.app/WhimWatch', 'PlugIns/WhimLiveActivity.appex/WhimLiveActivity', 'Watch/WhimWatch.app/PlugIns/WhimComplication.appex/WhimComplication'];
const fixtureMarkers = ['-WhimFixtureAudio', '-WhimFixtureWebhookURL', '-WhimFixtureOffline', '-WhimWatchTestID', '-WhimPeerScenario', '-WhimPlaybackFailureOnce', 'DebugFixtureRecorder', 'DebugFixtureTransport', 'DebugPeerTransport'];
export async function checkReleaseFixtures(root, app) {
  const errors = [];
  let approved;
  try {
    approved = await readFile(join(root, 'src/iphone/webhook-configuration/configuration-test.m4a'));
    if (!approved.length) throw new Error('Empty recording');
  } catch { errors.push('Missing product-owner-approved configuration-test.m4a recording'); }
  if (approved) {
    try {
      const runtime = await readFile(join(root, 'packages/WhimCore/Sources/WhimCore/WebhookConfiguration/Fixtures/configuration-test-fixture.m4a'));
      if (!approved.equals(runtime)) errors.push('Runtime configuration-test fixture does not match the approved recording');
    } catch { errors.push('Missing runtime configuration-test fixture'); }
  }
  if (!app) errors.push('Provide the Release whim.app path to inspect all four executables');
  else for (const executable of executables) {
    try {
      const bytes = await readFile(join(app, executable));
      if (!bytes.length) errors.push(`${executable}: empty Release executable`);
      for (const marker of fixtureMarkers) if (bytes.includes(Buffer.from(marker))) errors.push(`${executable}: contains DEBUG injection marker ${marker}`);
    } catch { errors.push(`${executable}: missing Release executable`); }
  }
  return errors;
}
if (process.argv[1] && import.meta.url === pathToFileURL(resolve(process.argv[1])).href) {
  const errors = await checkReleaseFixtures(process.cwd(), process.argv[2]);
  if (errors.length) { console.error(errors.join('\n')); process.exitCode = 1; }
  else console.log('Approved fixture and Release injection checks passed.');
}
