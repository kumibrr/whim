import assert from 'node:assert/strict';
import { chmod, readFile, writeFile } from 'node:fs/promises';
import { test } from 'node:test';
import { command, releaseFixture } from './release.test-support.mjs';

async function fixture(t, tag = '1.0.1') {
  const f = await releaseFixture(t);
  command(f.root, 'git', ['tag', '-a', tag, '-m', 'Original release source']);
  command(f.root, 'git', ['push', 'origin', `refs/tags/${tag}`]);
  const calls = [];
  const prs = [];
  const run = async (exe, args, opts) => {
    calls.push([exe, args]);
    if (exe === 'gh') {
      if (args[0] === 'pr' && args[1] === 'list') return JSON.stringify(prs);
      if (args[0] === 'pr' && args[1] === 'create') {
        prs.push({ url: 'https://github.com/fixture/whim/pull/1' });
        return prs[0].url;
      }
      throw Error(`Unexpected GitHub command ${args}`);
    }
    return command(opts.cwd, exe, args, opts);
  };
  return { ...f, tag, calls, prs, options: { run, repository: 'fixture/whim', log: () => {} } };
}
const remote = (f, ...args) => command(f.root, 'git', ['--git-dir', f.remote, ...args]).trim();
const prepare = async (f, opts = {}) => (await import('./prepare-cloud-release.mjs')).prepareCloudRelease(f.root, f.tag, { ...f.options, ...opts });
const resume = async f => (await import('./prepare-cloud-release.mjs')).resumeCloudRelease(f.root, f.options);

for (const tag of ['1.0.1', 'v1.0.1']) {
  test(`prepares ${tag} on main and the cloud branch while preserving the original tag; duplicate events are no-ops`, async t => {
    const f = await fixture(t, tag);
    const tagObject = remote(f, 'rev-parse', `refs/tags/${tag}`);
    await prepare(f);
    const prepared = remote(f, 'rev-parse', `refs/heads/release-build/${tag}`);
    assert.equal(remote(f, 'rev-parse', 'main'), prepared);
    assert.equal(remote(f, 'rev-parse', `${prepared}^`), f.initial);
    assert.equal(remote(f, 'rev-parse', `refs/tags/${tag}`), tagObject);
    assert.equal(JSON.parse(remote(f, 'show', `${prepared}:ios/package.json`)).version, '1.0.1');
    assert.equal(JSON.parse(remote(f, 'show', `${prepared}:package-lock.json`)).packages.ios.version, '1.0.1');
    assert.match(remote(f, 'show', `${prepared}:ios/whim.xcodeproj/project.pbxproj`), /MARKETING_VERSION = 1\.0\.1;/);
    assert.match(remote(f, 'show', `${prepared}:ios/CHANGELOG.md`), /## 1\.0\.1/);
    assert.deepEqual(JSON.parse(remote(f, 'show', `${prepared}:.release/prepared.json`)), { tag, source: f.initial, tagObject, version: '1.0.1' });
    assert.equal(remote(f, 'ls-tree', '-r', '--name-only', prepared, '.changeset/release-fixture.md'), '');
    await prepare(f);
    await resume(f);
    assert.equal(remote(f, 'rev-parse', 'main'), prepared);
    assert.equal(f.calls.filter(([exe]) => exe === 'npm').length, 1);
    assert.ok(!f.calls.some(([exe, args]) => exe === 'npm' && args.some(a => /test:|verify:/.test(a))));
    assert.equal(command(f.root, 'git', ['rev-parse', 'HEAD']).trim(), f.initial);
  });
}

for (const scenario of ['main advanced', 'tag version mismatch', 'invalid tag', 'no Changesets']) {
  test(`rejects ${scenario} without publishing a cloud branch`, async t => {
    const f = await fixture(t, scenario === 'tag version mismatch' ? '1.2.0' : '1.0.1');
    if (scenario === 'main advanced') {
      await writeFile(`${f.root}/new-source.txt`, 'Do not lose this source');
      command(f.root, 'git', ['add', '.']);
      command(f.root, 'git', ['commit', '-m', 'New source']);
      command(f.root, 'git', ['push', 'origin', 'HEAD:main']);
    }
    if (scenario === 'invalid tag') f.tag = '../main';
    if (scenario === 'no Changesets') {
      command(f.root, 'git', ['rm', '.changeset/release-fixture.md']);
      command(f.root, 'git', ['commit', '-m', 'No changesets']);
      command(f.root, 'git', ['push', 'origin', 'HEAD:main']);
      command(f.root, 'git', ['tag', '1.0.2']);
      command(f.root, 'git', ['push', 'origin', '1.0.2']);
      f.tag = '1.0.2';
    }
    await assert.rejects(prepare(f), /main|version|stable|Changeset/i);
    assert.equal(remote(f, 'for-each-ref', '--format=%(refname)', 'refs/heads/release-build/'), '');
  });
}

async function protectMain(f) {
  const hook = `${f.remote}/hooks/update`;
  await writeFile(hook, '#!/bin/sh\ncase "$1" in refs/heads/main) echo "GH006: Protected branch" >&2; exit 1;; esac\n');
  await chmod(hook, 0o755);
  return hook;
}

test('protected main waits for the actual squash-merged preparation, and retries reuse one PR', async t => {
  const f = await fixture(t);
  const hook = await protectMain(f);
  assert.equal((await prepare(f)).state, 'waiting-for-main');
  await prepare(f);
  assert.equal(f.prs.length, 1);
  assert.equal(remote(f, 'rev-parse', 'main'), f.initial);
  assert.equal(remote(f, 'for-each-ref', '--format=%(refname)', 'refs/heads/release-build/'), '');
  await writeFile(hook, '#!/bin/sh\nexit 0\n');
  command(f.root, 'git', ['fetch', 'origin', 'release-preparation/1.0.1']);
  const tree = command(f.root, 'git', ['rev-parse', 'FETCH_HEAD^{tree}']).trim();
  const merged = command(f.root, 'git', ['commit-tree', tree, '-p', f.initial, '-m', 'Squash preparation PR']).trim();
  command(f.root, 'git', ['push', 'origin', `${merged}:main`]);
  await resume(f);
  assert.equal(remote(f, 'rev-parse', 'release-build/1.0.1'), merged);
  await resume(f);
});

test('a preparation PR merged with newer source stops the cloud handoff without dropping main changes', async t => {
  const f = await fixture(t);
  const hook = await protectMain(f);
  await prepare(f);
  await writeFile(hook, '#!/bin/sh\nexit 0\n');
  command(f.root, 'git', ['fetch', 'origin', 'release-preparation/1.0.1']);
  command(f.root, 'git', ['switch', '--detach', 'FETCH_HEAD']);
  await writeFile(`${f.root}/new-source.txt`, 'Must survive');
  command(f.root, 'git', ['add', '.']);
  command(f.root, 'git', ['commit', '-m', 'Preparation merged with new source']);
  command(f.root, 'git', ['push', 'origin', 'HEAD:main']);
  await assert.rejects(resume(f), /main.*(advanced|differs)|source/i);
  assert.equal(remote(f, 'show', 'main:new-source.txt'), 'Must survive');
  assert.equal(remote(f, 'for-each-ref', '--format=%(refname)', 'refs/heads/release-build/'), '');
});

test('a lost successful atomic push response recovers idempotently', async t => {
  const f = await fixture(t);
  let lost = false;
  await prepare(f, { run: async (exe, args, opts) => {
    const result = await f.options.run(exe, args, opts);
    if (!lost && exe === 'git' && args.includes('--atomic')) { lost = true; throw Error('Connection lost'); }
    return result;
  } });
  await prepare(f);
  assert.equal(remote(f, 'rev-parse', 'main'), remote(f, 'rev-parse', 'release-build/1.0.1'));
});

test('main advancing during preparation leaves source untouched and withholds every prepared ref', async t => {
  const f = await fixture(t);
  let advanced = false;
  await assert.rejects(prepare(f, { run: async (exe, args, opts) => {
    const result = await f.options.run(exe, args, opts);
    if (!advanced && exe === 'npm') {
      advanced = true;
      const next = command(f.root, 'git', ['commit-tree', 'HEAD^{tree}', '-p', 'HEAD', '-m', 'Main advanced']).trim();
      command(f.root, 'git', ['push', 'origin', `${next}:main`]);
    }
    return result;
  } }), /main.*changed/i);
  assert.equal(remote(f, 'for-each-ref', '--format=%(refname)', 'refs/heads/release-'), '');
});

test('moved original tag and mismatching existing build refs stop retries', async t => {
  const f = await fixture(t);
  await prepare(f);
  command(f.root, 'git', ['tag', '-f', f.tag, remote(f, 'rev-parse', 'main')]);
  command(f.root, 'git', ['push', '--force', 'origin', `refs/tags/${f.tag}`]);
  await assert.rejects(prepare(f), /tag.*changed|provenance/i);
});

test('two tag spellings for the same version cannot publish competing releases', async t => {
  const f = await fixture(t);
  command(f.root, 'git', ['tag', 'v1.0.1']);
  command(f.root, 'git', ['push', 'origin', 'v1.0.1']);
  await prepare(f);
  f.tag = 'v1.0.1';
  await assert.rejects(prepare(f), /main.*advanced/i);
  assert.equal(remote(f, 'for-each-ref', '--format=%(refname)', 'refs/heads/release-build/v1.0.1'), '');
});

test('cloud checkout gate requires the immutable prepared branch and matching current main', async t => {
  const f = await fixture(t);
  await prepare(f);
  command(f.root, 'git', ['fetch', 'origin', 'release-build/1.0.1']);
  command(f.root, 'git', ['switch', '--detach', 'FETCH_HEAD']);
  const { verifyCloudRelease } = await import('./prepare-cloud-release.mjs');
  await verifyCloudRelease(f.root, 'release-build/1.0.1', f.options);
  await writeFile(`${f.root}/new-source.txt`, 'new source');
  command(f.root, 'git', ['add', '.']);
  command(f.root, 'git', ['commit', '-m', 'main advanced after handoff']);
  command(f.root, 'git', ['push', 'origin', 'HEAD:main']);
  await assert.rejects(verifyCloudRelease(f.root, 'release-build/1.0.1', f.options), /main|checkout/i);
});
