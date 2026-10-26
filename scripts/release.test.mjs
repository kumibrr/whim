import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { chmod, readFile, rm, writeFile } from 'node:fs/promises';
import { test } from 'node:test';
import { command, releaseFixture } from './release.test-support.mjs';

async function release(fixture, options = {}) {
  const module = await import('./release.mjs');
  return module.release(fixture.root, { ...fixture.options, ...options });
}

test('one release command publishes the validated version and its changelog from a clean release branch', async t => {
  const fixture = await releaseFixture(t);
  await release(fixture);
  const { root, remote } = fixture;
  const main = command(root, 'git', ['--git-dir', remote, 'rev-parse', 'main']).trim();
  const tag = command(root, 'git', ['--git-dir', remote, 'rev-parse', 'v1.0.1^{}']).trim();
  assert.equal(main, tag);
  assert.notEqual(main, fixture.initial);
  assert.equal(command(root, 'git', ['log', '-1', '--format=%s']).trim(), 'chore(ios): release 1.0.1');
  assert.equal(command(root, 'git', ['status', '--porcelain']), '');
  assert.deepEqual(fixture.validations, ['test:all', 'verify:release']);
  assert.equal(fixture.publications.length, 1);
  assert.equal(fixture.publications[0].tag, 'v1.0.1');
  assert.match(fixture.publications[0].notes, /^### Patch Changes\n\n- [a-f0-9]+: Recover Watch recordings\.$/);
  const manifest = JSON.parse(command(root, 'git', ['--git-dir', remote, 'show', 'main:ios/package.json']));
  assert.equal(manifest.version, '1.0.1');
  assert.equal(JSON.parse(await readFile(`${root}/package-lock.json`, 'utf8')).packages.ios.version, '1.0.1');
  assert.ok(fixture.messages.some(message => message.includes('https://github.com/fixture/whim/releases/tag/v1.0.1')));
});

for (const scenario of ['wrong platform', 'dirty checkout', 'staged unrelated file', 'detached HEAD', 'behind main', 'no Changesets', 'missing dependencies', 'wrong origin', 'existing local tag', 'existing remote tag']) {
  test(`preflight rejects ${scenario} without preparing or publishing a release`, async t => {
    const fixture = await releaseFixture(t);
    const { root } = fixture;
    let options = {};
    let expected;
    switch (scenario) {
      case 'wrong platform': options.platform = 'linux'; expected = /macOS/; break;
      case 'dirty checkout':
      case 'staged unrelated file':
        await writeFile(`${root}/unrelated.txt`, 'Keep this edit.');
        if (scenario.startsWith('staged')) command(root, 'git', ['add', 'unrelated.txt']);
        expected = /clean/; break;
      case 'detached HEAD': command(root, 'git', ['switch', '--detach']); expected = /branch/; break;
      case 'behind main': {
        const next = command(root, 'git', ['commit-tree', 'HEAD^{tree}', '-p', 'HEAD', '-m', 'Other change']).trim();
        command(root, 'git', ['push', 'origin', `${next}:main`]);
        expected = /origin\/main/; break;
      }
      case 'no Changesets':
        command(root, 'git', ['rm', '.changeset/release-fixture.md']);
        command(root, 'git', ['commit', '-m', 'No pending app release']);
        command(root, 'git', ['push', 'origin', 'HEAD:main']);
        expected = /Changeset/; break;
      case 'missing dependencies': await rm(`${root}/node_modules`); expected = /npm ci/; break;
      case 'wrong origin':
        options.run = (executable, args, opts) => executable === 'git' && args.join(' ') === 'remote get-url origin' ? 'https://gitlab.com/fixture/whim.git' : fixture.run(executable, args, opts);
        expected = /GitHub/; break;
      case 'existing local tag': command(root, 'git', ['tag', 'v1.0.1']); expected = /v1.0.1.*exist/; break;
      case 'existing remote tag':
        command(root, 'git', ['tag', 'v1.0.1']);
        command(root, 'git', ['push', 'origin', 'v1.0.1']);
        command(root, 'git', ['tag', '-d', 'v1.0.1']);
        expected = /v1.0.1.*exist/; break;
    }
    const before = command(root, 'git', ['rev-parse', 'HEAD']);
    await assert.rejects(release(fixture, options), expected);
    assert.equal(command(root, 'git', ['rev-parse', 'HEAD']), before);
    assert.equal(JSON.parse(await readFile(`${root}/ios/package.json`, 'utf8')).version, '1.0.0');
    assert.deepEqual(fixture.publications, []);
  });
}

for (const stage of ['test:all', 'verify:release']) {
  test(`${stage} failure preserves prepared changes without a release commit or tag`, async t => {
    const fixture = await releaseFixture(t);
    await assert.rejects(release(fixture, { run: async (executable, args, opts) => {
      if (executable === 'npm' && args[1] === stage) throw new Error(`${stage} failed`);
      return fixture.run(executable, args, opts);
    } }), /prepared files.*preserved/s);
    assert.equal(command(fixture.root, 'git', ['rev-parse', 'HEAD']).trim(), fixture.initial);
    assert.equal(command(fixture.root, 'git', ['--git-dir', fixture.remote, 'rev-parse', 'main']).trim(), fixture.initial);
    assert.equal(command(fixture.root, 'git', ['tag', '--list']), '');
    assert.equal(JSON.parse(await readFile(`${fixture.root}/ios/package.json`, 'utf8')).version, '1.0.1');
    assert.deepEqual(fixture.publications, []);
  });
}

for (const edit of ['unrelated.txt', 'ios/package.json', '.changeset/config.json']) {
  test(`concurrent edits to ${edit} during validation stop publication`, async t => {
    const fixture = await releaseFixture(t);
    await assert.rejects(release(fixture, { run: async (executable, args, opts) => {
      const result = await fixture.run(executable, args, opts);
      if (executable === 'npm' && args[1] === 'verify:release') await writeFile(`${fixture.root}/${edit}`, 'Concurrent edit\n');
      return result;
    } }), /changed|unexpected|concurrent/i);
    assert.equal(command(fixture.root, 'git', ['rev-parse', 'HEAD']).trim(), fixture.initial);
    assert.deepEqual(fixture.publications, []);
  });
}

test('main advancing during validation prevents a release commit', async t => {
  const fixture = await releaseFixture(t);
  await assert.rejects(release(fixture, { run: async (executable, args, opts) => {
    const result = await fixture.run(executable, args, opts);
    if (executable === 'npm' && args[1] === 'verify:release') {
      const next = command(fixture.root, 'git', ['commit-tree', 'HEAD^{tree}', '-p', 'HEAD', '-m', 'Concurrent main change']).trim();
      command(fixture.root, 'git', ['push', 'origin', `${next}:main`]);
    }
    return result;
  } }), /main.*changed|main.*advanced/i);
  assert.equal(command(fixture.root, 'git', ['rev-parse', 'HEAD']).trim(), fixture.initial);
  assert.deepEqual(fixture.publications, []);
});

for (const scenario of ['prerelease', 'prepared version mismatch', 'missing changelog heading', 'GitHub authentication', 'Apple tooling']) {
  test(`rejects ${scenario} before validation or publication`, async t => {
    const fixture = await releaseFixture(t);
    const run = async (executable, args, opts) => {
      if (scenario === 'GitHub authentication' && executable === 'gh' && args[0] === 'auth') throw new Error('Authentication failed');
      if (scenario === 'Apple tooling' && executable === 'bash') throw new Error('Apple tooling unavailable');
      const result = await fixture.run(executable, args, opts);
      if (scenario === 'prerelease' && args.includes('--output')) {
        const path = args[args.indexOf('--output') + 1];
        const plan = JSON.parse(await readFile(path, 'utf8'));
        plan.releases[0].newVersion = '1.0.1-beta.0';
        await writeFile(path, JSON.stringify(plan));
      }
      if (executable === 'npm' && args[1] === 'release:version') {
        if (scenario === 'prepared version mismatch') await writeFile(`${fixture.root}/ios/package.json`, '{"version":"2.0.0"}');
        if (scenario === 'missing changelog heading') await writeFile(`${fixture.root}/ios/CHANGELOG.md`, '# No release notes\n');
      }
      return result;
    };
    await assert.rejects(release(fixture, { run }), /stable|version|changelog|Authentication|Apple/i);
    assert.deepEqual(fixture.validations, []);
    assert.deepEqual(fixture.publications, []);
  });
}

test('a server rejecting the tag leaves both remote refs unchanged through an atomic push', async t => {
  const fixture = await releaseFixture(t);
  const hook = `${fixture.remote}/hooks/update`;
  await writeFile(hook, '#!/bin/sh\ncase "$1" in refs/tags/*) exit 1;; esac\n');
  await chmod(hook, 0o755);
  await assert.rejects(release(fixture), /local release commit.*preserved.*git push --atomic/s);
  assert.equal(command(fixture.root, 'git', ['--git-dir', fixture.remote, 'rev-parse', 'main']).trim(), fixture.initial);
  assert.equal(command(fixture.root, 'git', ['--git-dir', fixture.remote, 'tag', '--list']), '');
  assert.equal(command(fixture.root, 'git', ['tag', '--list']).trim(), 'v1.0.1');
  assert.deepEqual(fixture.publications, []);
});

test('GitHub publication failure explains that the tag is pushed and offers publication-only recovery', async t => {
  const fixture = await releaseFixture(t);
  await assert.rejects(release(fixture, { run: async (executable, args, opts) => {
    if (executable === 'gh' && args[0] === 'release') throw new Error('GitHub unavailable');
    return fixture.run(executable, args, opts);
  } }), /tag.*already pushed.*gh release create v1.0.1.*--verify-tag.*--notes-file/s);
  assert.equal(command(fixture.root, 'git', ['--git-dir', fixture.remote, 'rev-parse', 'v1.0.1^{}']), command(fixture.root, 'git', ['rev-parse', 'HEAD']));
  assert.deepEqual(fixture.publications, []);
});

test('CLI help is read-only and unsupported arguments fail instead of releasing', async () => {
  const path = new URL('./release.mjs', import.meta.url).pathname;
  const help = spawnSync(process.execPath, [path, '--help'], { encoding: 'utf8' });
  assert.equal(help.status, 0);
  assert.match(help.stdout, /npm run release/);
  const unknown = spawnSync(process.execPath, [path, '--dry-run'], { encoding: 'utf8' });
  assert.equal(unknown.status, 1);
  assert.match(unknown.stderr, /Unsupported argument/);
});
