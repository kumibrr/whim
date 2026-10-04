import { readFileSync } from 'node:fs';
import { pathToFileURL } from 'node:url';

// Xcode's Custom build location preference relocates products and intermediates even with -derivedDataPath.
export function xcodeBuildLocations(settings) {
  const app = settings.find((entry) => entry.target === 'whim')?.buildSettings;
  if (!app?.BUILD_DIR || !app?.PROJECT_TEMP_DIR) throw new Error('xcodebuild reported no build settings for the whim target.');
  return { products: app.BUILD_DIR, intermediates: app.PROJECT_TEMP_DIR };
}

if (import.meta.url === pathToFileURL(process.argv[1]).href) {
  const { products, intermediates } = xcodeBuildLocations(JSON.parse(readFileSync(0, 'utf8')));
  process.stdout.write(`${products}\n${intermediates}\n`);
}
