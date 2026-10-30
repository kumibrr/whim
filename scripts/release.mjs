import { resolve } from 'node:path';
import { pathToFileURL } from 'node:url';

// Kept as a read-only compatibility entry point: CI belongs to Xcode Cloud.
export async function release(_root = process.cwd(), { log = console.log } = {}) {
  log('Publish a GitHub Release at https://github.com/kumibrr/whim/releases/new using a new X.Y.Z (or vX.Y.Z) tag at current main. Commit app Changesets first; the tag must equal the next Changesets version.\nGitHub Actions prepares version/changelog/lockfile/Xcode metadata on main and release-build/<tag>. If main requires a PR, merge the generated preparation PR first. Xcode Cloud then runs all CI and archives the prepared branch.\nThis helper makes no changes, runs no local CI, and creates no release or tag. See docs/xcode-cloud.md.');
}

if (process.argv[1] && import.meta.url === pathToFileURL(resolve(process.argv[1])).href) {
  if (process.argv.length === 2 || (process.argv.length === 3 && process.argv[2] === '--help')) await release();
  else { console.error('Unsupported argument. Use npm run release -- --help for usage.'); process.exitCode = 1; }
}
