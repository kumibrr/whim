import { mkdtemp, mkdir, readFile, readdir, rm, symlink, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';
import { pathToFileURL } from 'node:url';
import { appVersion } from './check-release-metadata.mjs';
import { prepareReleaseVersion, runCommand } from './prepare-release-version.mjs';
import { isDataOnlyCommit, sourceTree as benchmarkSourceTree } from './benchmark-history.mjs';

export const provenancePath = '.release/prepared.json';
const versionFiles = ['ios/package.json', 'ios/CHANGELOG.md', 'package-lock.json', 'ios/whim.xcodeproj/project.pbxproj', provenancePath];
export function releaseVersion(tag) {
  if (!/^v?(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)$/.test(tag ?? '')) throw Error('Use a stable release tag: X.Y.Z or vX.Y.Z.');
  return tag.replace(/^v/, '');
}

function context(root, { run = runCommand, repository = process.env.GITHUB_REPOSITORY, log = console.log } = {}) {
  const execute = (exe, args, cwd = root) => run(exe, args, { cwd, capture: true });
  const git = async (...args) => (await execute('git', args)).trim();
  const tree = sha => git('rev-parse', `${sha}^{tree}`);
  const sourceTree = sha => benchmarkSourceTree(root, sha, { run });
  const dataOnlyAdvance = async (base, head) => {
    if (base === head) return true;
    await git('merge-base', '--is-ancestor', base, head);
    for (const sha of (await git('rev-list', `${base}..${head}`)).split('\n').filter(Boolean)) {
      if (!await isDataOnlyCommit(root, sha, { run })) return false;
    }
    return true;
  };
  const show = async (sha, path) => JSON.parse(await git('show', `${sha}:${path}`));
  async function state(tag) {
    const names = ['refs/heads/main', `refs/tags/${tag}`, `refs/heads/release-preparation/${tag}`, `refs/heads/release-build/${tag}`];
    const refs = new Map((await git('ls-remote', '--refs', 'origin', ...names)).split('\n').filter(Boolean).map(line => {
      const [sha, name] = line.split(/\s+/); return [name, sha];
    }));
    if (!refs.has(names[0]) || !refs.has(names[1])) throw Error('The release tag and origin/main must exist.');
    // Fetch exact observed objects, without changing any tag or user branch.
    await git('fetch', '--no-tags', 'origin', ...new Set(refs.values()));
    return { main: refs.get(names[0]), tagObject: refs.get(names[1]), source: await git('rev-parse', `${refs.get(names[1])}^{commit}`), preparation: refs.get(names[2]), build: refs.get(names[3]) };
  }
  async function verify(tag, current) {
    const prepared = current.preparation;
    if (!prepared) throw Error('Missing release preparation branch.');
    const metadata = await show(prepared, provenancePath);
    if (metadata.tag !== tag || metadata.version !== releaseVersion(tag) || metadata.source !== current.source || metadata.tagObject !== current.tagObject) throw Error('The original tag or release preparation provenance changed. Never move a release tag.');
    if (await git('show', '-s', '--format=%P', prepared) !== current.source) throw Error('Release preparation must have the original tagged source as its only parent.');
    if ((await show(prepared, 'ios/package.json')).version !== metadata.version) throw Error('Prepared app version does not match release tag.');
    const changed = (await git('diff', '--name-only', current.source, prepared)).split('\n');
    for (const path of changed) {
      if (versionFiles.includes(path)) continue;
      if (/^\.changeset\/[^/]+\.md$/.test(path) && path !== '.changeset/README.md' && await git('ls-tree', prepared, '--', path) === '') continue;
      throw Error(`Unexpected release preparation change: ${path}`);
    }
    if (current.build) {
      if (await sourceTree(current.build) !== await sourceTree(prepared)) throw Error('Existing release-build branch differs; it will never be overwritten.');
      await git('merge-base', '--is-ancestor', current.build, current.main);
    }
    return metadata;
  }
  return { execute, git, tree, sourceTree, dataOnlyAdvance, show, state, verify, repository, log };
}

async function includeBenchmarkHistory(c, current) {
  if (current.main === current.source) return current.preparation;
  const directory = await mkdtemp(join(tmpdir(), 'whim-release-benchmarks-'));
  const checkout = join(directory, 'checkout');
  try {
    await c.git('clone', '--quiet', '--no-checkout', '--no-hardlinks', '.', checkout);
    const local = async (...args) => (await c.execute('git', args, checkout)).trim();
    await local('read-tree', current.main);
    const patch = join(directory, 'version.patch');
    await writeFile(patch, await c.execute('git', ['diff', '--binary', current.source, current.preparation]));
    await local('apply', '--cached', patch);
    const tree = await local('write-tree');
    const commit = await local('-c', 'user.name=github-actions[bot]', '-c', 'user.email=41898282+github-actions[bot]@users.noreply.github.com',
      'commit-tree', tree, '-p', current.main, '-p', current.preparation, '-m', 'chore(ios): retain benchmark history during release preparation');
    await c.git('fetch', '--no-tags', checkout, commit);
    return commit;
  } finally { await rm(directory, { recursive: true, force: true }); }
}

async function handoff(c, tag, current, { allowMainPush }) {
  await c.verify(tag, current);
  if (current.build) return { state: 'ready', commit: current.build };
  if (await c.sourceTree(current.main) === await c.sourceTree(current.preparation)) {
    // Squash/rebase/merge PRs are all supported: publish the commit actually on main.
    try { await c.git('push', '--force-with-lease=' + `refs/heads/release-build/${tag}:`, 'origin', `${current.main}:refs/heads/release-build/${tag}`); }
    catch (error) {
      const after = await c.state(tag);
      if (!after.build || after.build !== current.main) throw error;
      await c.verify(tag, after);
    }
    c.log(`Ready for Xcode Cloud: release-build/${tag} at ${current.main}.`);
    return { state: 'ready', commit: current.main };
  }
  if (await c.sourceTree(current.main) !== await c.sourceTree(current.source)) throw Error('main advanced or differs from the tagged source. Cloud handoff stopped; publish a new release tag from reconciled main. Do not move the original tag.');
  await c.git('merge-base', '--is-ancestor', current.source, current.main);
  if (allowMainPush) {
    const publication = await includeBenchmarkHistory(c, current);
    try {
      // Both refs become visible together. A protected/rejected main leaves neither changed.
      await c.git('push', '--atomic', `--force-with-lease=refs/heads/release-build/${tag}:`, 'origin', `${publication}:refs/heads/main`, `${publication}:refs/heads/release-build/${tag}`);
      return { state: 'ready', commit: publication };
    } catch (error) {
      const after = await c.state(tag);
      if (after.build) { await c.verify(tag, after); return { state: 'ready', commit: after.build }; }
      if (after.main !== current.main) return handoff(c, tag, after, { allowMainPush: false });
      c.log(`Atomic main update was rejected: ${error.message}. Preparing a main PR instead.`);
    }
  }
  if (!c.repository || !/^[\w.-]+\/[\w.-]+$/.test(c.repository)) throw Error('Set GITHUB_REPOSITORY to create the required main preparation PR.');
  const head = `release-preparation/${tag}`;
  const existing = JSON.parse(await c.execute('gh', ['pr', 'list', '--repo', c.repository, '--base', 'main', '--head', head, '--state', 'open', '--json', 'url']));
  let url = existing[0]?.url;
  if (!url) {
    const directory = await mkdtemp(join(tmpdir(), 'whim-cloud-pr-'));
    try {
      const path = join(directory, 'body.md');
      await writeFile(path, `Prepare ${tag} from immutable source ${current.source}.\n\nMerge this generated version/changelog/lockfile/Xcode metadata update into main. Xcode Cloud release-build/${tag} is withheld until main contains exactly the prepared tree. If source advances, stop and publish a new tag from reconciled main.\n`);
      url = (await c.execute('gh', ['pr', 'create', '--repo', c.repository, '--base', 'main', '--head', head, '--title', `chore(ios): prepare ${tag}`, '--body-file', path])).trim();
    } finally { await rm(directory, { recursive: true, force: true }); }
  }
  c.log(`Waiting for main preparation PR: ${url}. No release-build branch has been published.`);
  return { state: 'waiting-for-main', url };
}

export async function prepareCloudRelease(root = process.cwd(), tag, options = {}) {
  const version = releaseVersion(tag);
  const c = context(root, options);
  let current = await c.state(tag);
  if (!current.preparation) {
    if (current.build) throw Error('Existing release-build branch has no preparation provenance; refusing to overwrite.');
    if (await c.sourceTree(current.main) !== await c.sourceTree(current.source) || !await c.dataOnlyAdvance(current.source, current.main)) throw Error('The release tag must match current origin/main. main advanced; publish a new tag after reconciling source.');
    await c.git('merge-base', '--is-ancestor', current.source, current.main);
    const directory = await mkdtemp(join(tmpdir(), 'whim-cloud-version-'));
    const checkout = join(directory, 'checkout');
    try {
      await c.git('clone', '--no-hardlinks', '--no-checkout', root, checkout);
      const local = async (...args) => (await c.execute('git', args, checkout)).trim();
      await local('checkout', '--detach', current.source);
      await symlink(join(root, 'node_modules'), join(checkout, 'node_modules'));
      const changesets = (await readdir(join(checkout, '.changeset'))).filter(name => name.endsWith('.md') && name !== 'README.md');
      if (!changesets.length) throw Error('No pending app Changesets.');
      const before = await appVersion(checkout);
      const prepared = await prepareReleaseVersion(checkout, (exe, args, opts) => c.execute(exe, args, opts.cwd));
      if (prepared !== version || version.localeCompare(before, 'en', { numeric: true }) <= 0) throw Error(`Tag version ${version} must match the advancing Changesets version ${prepared}.`);
      const notes = await readFile(join(checkout, 'ios/CHANGELOG.md'), 'utf8');
      if (!notes.includes(`## ${version}\n`)) throw Error('The prepared changelog is missing the release version.');
      await mkdir(join(checkout, '.release'), { recursive: true });
      await writeFile(join(checkout, provenancePath), JSON.stringify({ tag, source: current.source, tagObject: current.tagObject, version }, null, 2) + '\n');
      await local('add', '--', ...versionFiles, ...changesets.map(name => `.changeset/${name}`));
      const tree = await local('write-tree');
      const commit = await local('-c', 'user.name=github-actions[bot]', '-c', 'user.email=41898282+github-actions[bot]@users.noreply.github.com', 'commit-tree', tree, '-p', current.source, '-m', `chore(ios): prepare ${tag}`);
      await c.git('fetch', '--no-tags', checkout, commit);
      await c.verify(tag, { ...current, preparation: commit });
      const latest = await c.state(tag);
      if (!await c.dataOnlyAdvance(current.main, latest.main) || latest.tagObject !== current.tagObject) throw Error('main or the original tag changed during version preparation; publication stopped.');
      await c.git('merge-base', '--is-ancestor', current.main, latest.main);
      try { await c.git('push', `--force-with-lease=refs/heads/release-preparation/${tag}:`, 'origin', `${commit}:refs/heads/release-preparation/${tag}`); }
      catch (error) {
        const after = await c.state(tag);
        if (!after.preparation || await c.tree(after.preparation) !== tree) throw error;
      }
    } finally { await rm(directory, { recursive: true, force: true }); }
    current = await c.state(tag);
  }
  return handoff(c, tag, current, { allowMainPush: true });
}

export async function resumeCloudRelease(root = process.cwd(), options = {}) {
  const c = context(root, options);
  await c.git('fetch', '--no-tags', 'origin', 'main');
  const main = await c.git('rev-parse', 'FETCH_HEAD');
  if (!await c.git('ls-tree', main, '--', provenancePath)) return { state: 'idle' };
  const { tag } = await c.show(main, provenancePath);
  releaseVersion(tag);
  return handoff(c, tag, await c.state(tag), { allowMainPush: false });
}

export async function verifyCloudRelease(root, branch, options = {}) {
  const tag = branch.replace(/^release-build\//, '');
  releaseVersion(tag);
  if (branch !== `release-build/${tag}`) throw Error('Cloud must build a release-build/<tag> branch.');
  const c = context(root, options);
  if (await c.git('rev-parse', '--is-shallow-repository') === 'true') await c.git('fetch', '--unshallow', '--no-tags', 'origin');
  const current = await c.state(tag);
  await c.verify(tag, current);
  const head = await c.git('rev-parse', 'HEAD');
  if (!current.build || current.build !== head || await c.sourceTree(current.main) !== await c.sourceTree(head)) throw Error('Cloud checkout or current main differs from the prepared release. Refusing stale source.');
}

if (process.argv[1] && import.meta.url === pathToFileURL(resolve(process.argv[1])).href) {
  try {
    if (process.argv.length === 3 && process.argv[2] === '--resume') await resumeCloudRelease();
    else if (process.argv.length === 3) await prepareCloudRelease(process.cwd(), process.argv[2]);
    else throw Error('Usage: node scripts/prepare-cloud-release.mjs <X.Y.Z|vX.Y.Z|--resume>');
  } catch (error) { console.error(error.message); process.exitCode = 1; }
}
