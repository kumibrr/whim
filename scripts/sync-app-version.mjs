import { readFile, writeFile } from 'node:fs/promises';
import { join, resolve } from 'node:path';
import { pathToFileURL } from 'node:url';
import { appVersion } from './check-release-metadata.mjs';

// Runs after `changeset version` so every Xcode target ships the released marketing version.
export async function syncAppVersion(root = process.cwd()) {
  const version = await appVersion(root);
  const path = join(root, 'ios/whim.xcodeproj/project.pbxproj');
  const project = await readFile(path, 'utf8');
  await writeFile(path, project.replace(/MARKETING_VERSION = [^;]+;/g, `MARKETING_VERSION = ${version};`));
  return version;
}

if (process.argv[1] && import.meta.url === pathToFileURL(resolve(process.argv[1])).href) {
  console.log(`Xcode marketing version set to ${await syncAppVersion(process.argv[2] ?? process.cwd())}.`);
}
