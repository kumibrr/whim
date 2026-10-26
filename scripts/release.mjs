import { access, mkdtemp, readFile, readdir, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';
import { pathToFileURL } from 'node:url';
import { appVersion } from './check-release-metadata.mjs';
import { runCommand } from './prepare-release-version.mjs';

const cloudWorkflow = 'https://appstoreconnect.apple.com/teams/3a7fa4a7-7fbd-40c9-b79c-659659e627f6/xcode-cloud/products/b675c35b-56c1-482b-b43d-ac966e431519/workflows/62dc6f87-fa57-4e9e-810a-43aa1dd13728';
const versionFiles = ['ios/package.json', 'ios/CHANGELOG.md', 'package-lock.json', 'ios/whim.xcodeproj/project.pbxproj'];
const shellQuote = value => "'" + value.replaceAll("'", "'\\''") + "'";

export async function release(root = process.cwd(), { run = runCommand, platform = process.platform, log = console.log } = {}) {
  const execute = (command, args, capture = false) => run(command, args, { cwd: root, capture });
  if (platform !== 'darwin') throw new Error('Releases require macOS and Xcode.');
  try { await access(join(root, 'node_modules/@changesets/cli/bin.js')); }
  catch { throw new Error('Install dependencies with npm ci before releasing.'); }
  if ((await execute('git', ['status', '--porcelain'], true)).trim()) throw new Error('Start a release from a clean checkout; commit or stash your changes first.');
  try { await execute('git', ['symbolic-ref', '--quiet', '--short', 'HEAD'], true); }
  catch { throw new Error('Start a release from a branch, not a detached HEAD.'); }
  await execute('git', ['fetch', '--no-tags', 'origin', 'main']);
  const initial = (await execute('git', ['rev-parse', 'HEAD'], true)).trim();
  if (initial !== (await execute('git', ['rev-parse', 'refs/remotes/origin/main'], true)).trim()) throw new Error('The current commit must match origin/main before releasing.');
  const origin = (await execute('git', ['remote', 'get-url', 'origin'], true)).trim();
  const repository = origin.match(/^(?:git@github\.com:|https:\/\/github\.com\/)([A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+?)(?:\.git)?$/)?.[1];
  if (!repository) throw new Error('The origin remote must identify a GitHub repository.');
  await execute('gh', ['auth', 'status', '--hostname', 'github.com']);
  await execute('gh', ['repo', 'view', repository, '--json', 'nameWithOwner', '--jq', '.nameWithOwner'], true);
  await execute('bash', ['-c', 'source ./scripts/apple-toolchain.sh && xcrun --find xcodebuild']);
  const temporaryPlan = await mkdtemp(join(tmpdir(), 'whim-release-plan-'));
  let planned;
  try {
    const path = join(temporaryPlan, 'plan.json');
    await execute(process.execPath, [join(root, 'node_modules/@changesets/cli/bin.js'), 'status', '--output', path], true);
    planned = JSON.parse(await readFile(path, 'utf8')).releases.find(item => item.name === '@whim/app');
  } finally { await rm(temporaryPlan, { recursive: true, force: true }); }
  if (!planned || planned.type === 'none') throw new Error('No pending app Changesets; record the release changes with npm run changeset first.');
  const version = planned.newVersion;
  const before = await appVersion(root);
  if (!/^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)$/.test(version) || version.localeCompare(before, 'en', { numeric: true }) <= 0) throw new Error('A release must advance to a stable app version.');
  const tag = `v${version}`;
  if ((await execute('git', ['tag', '--list', tag], true)).trim() || (await execute('git', ['ls-remote', '--tags', 'origin', `refs/tags/${tag}`], true)).trim()) throw new Error(`${tag} already exists; release tags must never be moved.`);
  const changesets = (await readdir(join(root, '.changeset'))).filter(name => name.endsWith('.md') && name !== 'README.md').map(name => `.changeset/${name}`);
  const allowed = [...versionFiles, ...changesets];
  let prepared = false;
  let committed = false;
  let pushed = false;
  let notesPath;
  const pushCommand = `git push --atomic origin HEAD:refs/heads/main refs/tags/${tag}`;
  const publishCommand = () => `gh release create ${tag} --repo ${repository} --verify-tag --title ${shellQuote(`whim ${version}`)} --notes-file ${shellQuote(notesPath)}`;
  const snapshot = async () => {
    const changed = (await execute('git', ['diff', '--name-only', '-z', 'HEAD'], true)).split('\0').filter(Boolean);
    const untracked = (await execute('git', ['ls-files', '--others', '--exclude-standard', '-z'], true)).split('\0').filter(Boolean);
    if ([...changed, ...untracked].some(path => !allowed.includes(path))) throw new Error('Unexpected files changed during release preparation or validation.');
    return JSON.stringify(await Promise.all(allowed.map(async path => {
      try { return [path, await readFile(join(root, path), 'utf8')]; }
      catch (error) { if (error.code === 'ENOENT') return [path, null]; throw error; }
    })));
  };
  try {
    prepared = true;
    log(`Preparing whim ${version}.`);
    await execute('npm', ['run', 'release:version']);
    if (await appVersion(root) !== version) throw new Error('The prepared app version does not match the Changesets release plan.');
    const changelog = (await readFile(join(root, 'ios/CHANGELOG.md'), 'utf8')).replaceAll('\r\n', '\n');
    const heading = `## ${version}\n`;
    if (!changelog.includes(heading)) throw new Error(`The changelog is missing version ${version}.`);
    const notes = changelog.slice(changelog.indexOf(heading) + heading.length).split(/^## /m)[0].trim();
    if (!notes) throw new Error(`The changelog has no release notes for ${version}.`);
    const temporary = await mkdtemp(join(tmpdir(), 'whim-release-notes-'));
    notesPath = join(temporary, 'notes.md');
    await writeFile(notesPath, notes);
    const preparedFiles = await snapshot();
    await execute('npm', ['run', 'test:all']);
    await execute('npm', ['run', 'verify:release']);
    if (await snapshot() !== preparedFiles) throw new Error('Prepared files changed concurrently during validation; review the edits and validate again.');
    await execute('git', ['fetch', '--no-tags', 'origin', 'main']);
    if ((await execute('git', ['rev-parse', 'HEAD'], true)).trim() !== initial || (await execute('git', ['rev-parse', 'refs/remotes/origin/main'], true)).trim() !== initial) throw new Error('HEAD or origin/main changed during validation; update the checkout and validate again.');
    await execute('git', ['add', '--', ...allowed]);
    await execute('git', ['commit', '-m', `chore(ios): release ${version}`]);
    committed = true;
    if ((await execute('git', ['status', '--porcelain'], true)).trim()) throw new Error('Unexpected edits appeared while committing the release.');
    await execute('git', ['tag', '-a', tag, '-m', `whim ${version}`]);
    await execute('git', ['push', '--atomic', 'origin', 'HEAD:refs/heads/main', `refs/tags/${tag}`]);
    pushed = true;
    const url = await execute('gh', ['release', 'create', tag, '--repo', repository, '--verify-tag', '--title', `whim ${version}`, '--notes-file', notesPath], true);
    log(`Published ${url.trim()}\nThe version tag triggers the Xcode Cloud archive and upload: ${cloudWorkflow}`);
    await rm(temporary, { recursive: true, force: true });
  } catch (error) {
    let recovery = '';
    if (pushed) recovery = `The tag ${tag} is already pushed and has triggered Xcode Cloud. Check whether the GitHub Release exists, then recover publication only:\ngh release view ${tag} --repo ${repository}\n${publishCommand()}\nDo not run versioning again.`;
    else if (committed) recovery = `The local release commit and any tag are preserved. Inspect local and remote refs before retrying; a connection failure can hide a successful push:\ngit ls-remote origin refs/heads/main refs/tags/${tag}\n${pushCommand}\nThen publish: ${publishCommand()}\nDo not run versioning again.`;
    else if (prepared) recovery = `The prepared files are preserved. Review git diff, resolve the failure, and rerun npm run test:all and npm run verify:release. Finish the reviewed commit/tag/push using the recovery procedure in README.md; do not run versioning again.${notesPath ? `\nRelease notes: ${notesPath}` : ''}`;
    throw new Error(`${error.message}\n${recovery}`, { cause: error });
  }
}

if (process.argv[1] && import.meta.url === pathToFileURL(resolve(process.argv[1])).href) {
  try {
    if (process.argv.length === 3 && process.argv[2] === '--help') console.log('Usage: npm run release\nConsumes pending Changesets, validates, commits, pushes main and the version tag, and publishes a GitHub Release. Requires a clean macOS checkout matching origin/main.');
    else if (process.argv.length > 2) throw new Error('Unsupported argument. Use npm run release -- --help for usage.');
    else await release();
  }
  catch (error) { console.error(error.message); process.exitCode = 1; }
}
