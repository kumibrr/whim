import assert from 'node:assert/strict';
import { execFile } from 'node:child_process';
import { mkdtemp, mkdir, readFile, writeFile, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { promisify } from 'node:util';
import { test } from 'node:test';
import { appendResults, freezeSnapshot, verifyObservation } from './benchmark-history.mjs';
import { metricIDs } from './benchmark-metrics.mjs';

const exec = promisify(execFile);
const policy = JSON.parse(await readFile(new URL('../benchmarks/policy.json', import.meta.url)));
const start = '<!-- whim:performance:start -->', end = '<!-- whim:performance:end -->';
async function fixture(t) {
  const root = await mkdtemp(join(tmpdir(), 'whim-release-report-'));
  t.after(() => rm(root, { recursive: true, force: true }));
  const git = async (...args) => (await exec('git', args, { cwd: root })).stdout.trim();
  await git('init', '-b', 'main'); await git('config', 'user.name', 'Fixture'); await git('config', 'user.email', 'fixture@example.invalid');
  const commit = async message => { await git('add', '.'); await git('commit', '-m', message); return git('rev-parse', 'HEAD'); };
  await writeFile(join(root, 'app.swift'), 'original'); const legacy = await commit('legacy');
  await git('tag', '1.0.0', legacy);
  await mkdir(join(root, 'benchmarks')); await writeFile(join(root, 'benchmarks/policy.json'), JSON.stringify(policy));
  const source = await commit('benchmark-enabled source');
  const remote = `${root}-remote.git`;
  t.after(() => rm(remote, { recursive: true, force: true }));
  await exec('git', ['init', '--bare', '--initial-branch=main', remote]);
  await git('remote', 'add', 'origin', remote);
  let number = 0;
  const measure = async (sha = source, options = {}) => {
    number++;
    const frozen = await freezeSnapshot(root, sha, 'HEAD');
    const baseline = frozen.candidates[0];
    const raw = { schemaVersion: 1, protocol: policy.protocol, fixture: policy.fixture,
      source: { sha, parents: (await git('show', '-s', '--format=%P', sha)).split(' ').filter(Boolean),
        context: options.context ?? 'main', committedAt: await git('show', '-s', '--format=%cI', sha) },
      run: { id: `11111111-1111-4111-8111-${String(number).padStart(12, '0')}`, number,
        measuredAt: options.measuredAt ?? new Date(Date.UTC(2026, 10, 15, 0, number)).toISOString(),
        url: 'https://appstoreconnect.apple.com/teams/test/xcode-cloud/builds/test' },
      environment: { architecture: 'arm64', cpu: 'Apple M4', macOS: '27.2', kernel: '27.2.0',
        device: options.device ?? 'iPhone 16 Pro', runtime: 'iOS 27.0', xcode: 'Xcode 27.1', configuration: policy.configuration },
      snapshot: { historySHA: frozen.historySHA, policyHash: frozen.policyHash,
        baselinePath: baseline?.path ?? null, baselineHash: baseline?.hash ?? null },
      metrics: Object.fromEntries(metricIDs.map(id => [id, { batches: options.batches ?? [Array(10).fill(options.ms ?? 1000)] }])) };
    if (options.failure) { raw.failure = { code: 'measurementFailed' }; raw.metrics = {}; }
    const record = await verifyObservation(root, raw);
    await appendResults(root, [record]); await commit('benchmark results');
    return record;
  };
  const release = { id: 42, tag_name: 'v1.1.0', draft: false, prerelease: false, body: 'Human release notes.\n' };
  const calls = [];
  const github = async (method, path, body) => {
    calls.push({ method, path, body });
    if (method === 'GET' && path.includes('/releases?')) return [structuredClone(release)];
    if (method === 'GET' && path.endsWith('/releases/42')) return structuredClone(release);
    if (method === 'PATCH' && path.endsWith('/releases/42')) { release.body = body.body; return structuredClone(release); }
    throw Error(`Unexpected API request: ${method} ${path}`);
  };
  const push = async () => { await git('push', 'origin', 'main', '--tags'); };
  const sync = async (options = {}) => (await import('./benchmark-release.mjs')).syncReleaseBenchmarks(root,
    { repository: 'owner/repo', github, log: () => {}, ...options });
  return { root, git, commit, source, legacy, measure, release, calls, github, push, sync };
}

test('release summary uses equivalent tagged main code, preserves notes and is idempotent', async t => {
  const f = await fixture(t);
  const record = await f.measure();
  const tagged = await f.git('rev-parse', 'HEAD');
  await f.git('tag', '-a', f.release.tag_name, '-m', 'Immutable tag', tagged); await f.push();
  const original = f.release.body;
  assert.deepEqual(await f.sync(), { updated: 1 });
  assert.ok(f.release.body.startsWith(original));
  assert.match(f.release.body, /\| Launch \(empty\) \| 1000 ms \| n\/a \|/);
  assert.match(f.release.body, /\| Stop → saved Note \| 1000 ms \| n\/a \|/);
  assert.match(f.release.body, /10 samples per batch/);
  assert.match(f.release.body, /iPhone simulator.*optimized-debug/);
  assert.ok(f.release.body.includes(record.source.sha.slice(0, 7)));
  assert.ok(f.release.body.includes(`benchmarks/results/${f.source}/${record.run.id}.json`));
  assert.deepEqual(Object.keys(f.calls.find(call => call.method === 'PATCH').body), ['body']);
  f.calls.length = 0;
  assert.deepEqual(await f.sync(), { updated: 0 });
  assert.ok(!f.calls.some(call => call.method === 'PATCH'));
  assert.equal(await f.git('rev-parse', `${f.release.tag_name}^{commit}`), tagged);
});

test('unmeasured changed source stays pending until its exact results arrive', async t => {
  const f = await fixture(t); await f.measure();
  await writeFile(join(f.root, 'app.swift'), 'new behavior'); const changed = await f.commit('changed app');
  await f.git('tag', f.release.tag_name, changed); await f.push();
  await f.sync();
  assert.match(f.release.body, /pending/i); assert.doesNotMatch(f.release.body, /1000 ms/);
  await f.measure(changed, { ms: 1100 }); await f.push();
  await f.sync();
  assert.match(f.release.body, /1100 ms.*\+10\.0%/);
  assert.equal(f.release.body.split(start).length, 2);
  assert.equal(f.release.body.split(end).length, 2);
  assert.ok(f.release.body.startsWith('Human release notes.\n'));
});

test('latest failed attempt is reported instead of silently reusing older success', async t => {
  const f = await fixture(t); await f.measure(); await f.measure(f.source, { failure: true });
  await f.git('tag', f.release.tag_name, f.source); await f.push(); await f.sync();
  assert.match(f.release.body, /failed/i); assert.doesNotMatch(f.release.body, /1000 ms/);
});

test('latest attempt is ordered by its instant rather than timestamp spelling', async t => {
  const f = await fixture(t); await f.measure();
  await f.measure(f.source, { failure: true, measuredAt: '2026-11-14T23:30:00-02:00' });
  await f.git('tag', f.release.tag_name, f.source); await f.push(); await f.sync();
  assert.match(f.release.body, /failed/i); assert.doesNotMatch(f.release.body, /1000 ms/);
});

test('statistics retain their frozen sample policy and baseline after policy advances', async t => {
  const f = await fixture(t); await f.measure();
  await writeFile(join(f.root, 'app.swift'), 'next source'); const source = await f.commit('next source');
  await f.measure(source, { ms: 1100 }); await f.git('tag', f.release.tag_name, source);
  await writeFile(join(f.root, 'benchmarks/policy.json'), JSON.stringify({ ...policy, samples: 5 }));
  await f.commit('new sampling policy'); await f.push(); await f.sync();
  assert.match(f.release.body, /10 samples per batch/); assert.match(f.release.body, /1100 ms.*\+10\.0%/);
});

for (const scenario of ['regression', 'inconclusive']) test(`complete ${scenario} measurements remain visibly qualified`, async t => {
  const f = await fixture(t); await f.measure();
  await writeFile(join(f.root, 'app.swift'), scenario); const source = await f.commit(scenario);
  const batches = scenario === 'regression' ? [Array(10).fill(1300), Array(10).fill(1300)]
    : [Array.from({ length: 10 }, (_, i) => i % 2 ? 1500 : 500)];
  await f.measure(source, { batches }); await f.git('tag', f.release.tag_name, source); await f.push(); await f.sync();
  assert.match(f.release.body, scenario === 'regression' ? /Regression detected/ : /Inconclusive/);
  assert.match(f.release.body, scenario === 'regression' ? /1300 ms.*\+30\.0%/ : /1000 ms.*\+0\.0%/);
});

test('environment metadata cannot inject table columns or HTML', async t => {
  const f = await fixture(t); await f.measure(f.source, { device: 'iPhone | <test>' });
  await f.git('tag', f.release.tag_name, f.source); await f.push(); await f.sync();
  assert.ok(f.release.body.includes('iPhone \\| &lt;test&gt;'));
  assert.doesNotMatch(f.release.body, /<test>/);
});

test('API publication failures are visible and can be retried without losing notes', async t => {
  const f = await fixture(t); await f.git('tag', f.release.tag_name, f.source); await f.push();
  let denied = true;
  const github = async (method, path, body) => {
    if (method === 'PATCH' && denied) throw Error('Write denied');
    return f.github(method, path, body);
  };
  await assert.rejects(f.sync({ github }), /Write denied/); assert.equal(f.release.body, 'Human release notes.\n');
  denied = false;
  assert.deepEqual(await f.sync({ github }), { updated: 1 });
  assert.ok(f.release.body.startsWith('Human release notes.\n'));
});

test('a moved tag stops publication rather than attributing old statistics to new code', async t => {
  const f = await fixture(t); await f.git('tag', f.release.tag_name, f.source); await f.push();
  const github = async (method, path, body) => {
    if (method === 'GET' && path.endsWith('/releases/42')) {
      await writeFile(join(f.root, 'app.swift'), 'moved tag source'); const changed = await f.commit('new source');
      await f.git('tag', '-f', f.release.tag_name, changed);
      await f.git('push', '--force', 'origin', `refs/tags/${f.release.tag_name}`);
    }
    return f.github(method, path, body);
  };
  await assert.rejects(f.sync({ github }), /tag changed/i);
  assert.ok(!f.calls.some(call => call.method === 'PATCH'));
});

test('a PR-only observation cannot become release statistics', async t => {
  const f = await fixture(t); await f.measure(f.source, { context: 'pr/7' });
  await f.git('tag', f.release.tag_name, f.source); await f.push(); await f.sync();
  assert.match(f.release.body, /pending/i); assert.doesNotMatch(f.release.body, /1000 ms/);
});

for (const mode of ['draft', 'prerelease', 'legacy', 'unsafe']) test(`${mode} releases are left untouched`, async t => {
  const f = await fixture(t);
  if (mode === 'draft' || mode === 'prerelease') f.release[mode] = true;
  if (mode === 'legacy') f.release.tag_name = '1.0.0';
  if (mode === 'unsafe') f.release.tag_name = '$(touch /tmp/not-a-tag)';
  await f.push(); const original = f.release.body;
  assert.deepEqual(await f.sync(), { updated: 0 }); assert.equal(f.release.body, original);
  assert.ok(!f.calls.some(call => call.method === 'PATCH'));
});

for (const body of [`Text\n${start}\nUnclosed`, `${end}\n${start}`, `${start}${end}${start}${end}`]) {
  test('malformed managed sections fail without replacing human notes', async t => {
    const f = await fixture(t); await f.git('tag', f.release.tag_name, f.source); await f.push(); f.release.body = body;
    await assert.rejects(f.sync(), /marker|section/i);
    assert.equal(f.release.body, body); assert.ok(!f.calls.some(call => call.method === 'PATCH'));
  });
}

test('refreshes the release body before patching and preserves edits outside its section', async t => {
  const f = await fixture(t); await f.git('tag', f.release.tag_name, f.source); await f.push();
  const github = async (method, path, body) => {
    if (method === 'GET' && path.includes('/releases?')) return [structuredClone(f.release)];
    if (method === 'GET') return { ...f.release, body: `Recent edit\n${start}\nOld report\n${end}\nHuman footer` };
    if (method === 'PATCH') { f.release.body = body.body; return f.release; }
    throw Error('Unexpected method');
  };
  await f.sync({ github });
  assert.ok(f.release.body.startsWith('Recent edit\n')); assert.ok(f.release.body.endsWith('\nHuman footer'));
  assert.doesNotMatch(f.release.body, /Old report/);
});
