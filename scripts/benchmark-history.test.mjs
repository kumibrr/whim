import assert from 'node:assert/strict';
import { execFile } from 'node:child_process';
import { mkdtemp, mkdir, readFile, writeFile, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { promisify } from 'node:util';
import { test } from 'node:test';

const exec = promisify(execFile);
const policy = JSON.parse(await readFile(new URL('../benchmarks/policy.json', import.meta.url)));
const ids = ['launch.empty', 'launch.populated', 'record.populated', 'stop.populated', 'timeline.populated'];
async function repository(t) {
  const root = await mkdtemp(join(tmpdir(), 'whim-benchmark-git-'));
  t.after(() => rm(root, { force: true, recursive: true }));
  const git = async (...args) => (await exec('git', args, { cwd: root })).stdout.trim();
  await git('init', '-b', 'main');
  await git('config', 'user.email', 'test@example.com'); await git('config', 'user.name', 'Test');
  await mkdir(join(root, 'benchmarks'));
  await writeFile(join(root, 'benchmarks/policy.json'), JSON.stringify(policy));
  await writeFile(join(root, 'app.swift'), 'source');
  await git('add', '.'); await git('commit', '-m', 'source');
  return { root, git, sha: await git('rev-parse', 'HEAD') };
}

async function observation(h, id = '11111111-1111-4111-8111-111111111111') {
  const { contentHash } = await import('./benchmark-history.mjs');
  return { schemaVersion: 1, protocol: policy.protocol, fixture: policy.fixture,
    source: { sha: h.sha, parents: [], context: 'main', committedAt: await h.git('show', '-s', '--format=%cI', h.sha) },
    run: { id, number: 1, url: 'https://appstoreconnect.apple.com/teams/test/xcode-cloud/builds/test', measuredAt: '2026-11-13T12:05:00Z' },
    environment: { architecture: 'arm64', cpu: 'Apple M4', macOS: '27.0', kernel: '26.0', xcode: '27A9275', runtime: 'iOS 27.0', device: 'iPhone 16 Pro', configuration: policy.configuration },
    snapshot: { historySHA: h.sha, policyHash: contentHash(policy), baselinePath: null, baselineHash: null },
    metrics: Object.fromEntries(ids.map(id => [id, { batches: [Array(10).fill(1000)] }])) };
}

test('history validates raw observations and never accepts an incomplete/forged baseline', async t => {
  const h = await repository(t);
  const { validateObservation, verifyObservation } = await import('./benchmark-history.mjs');
  const value = await observation(h);
  assert.equal(validateObservation(value, policy), value);
  const record = await verifyObservation(h.root, value);
  assert.equal(record.evaluation.outcome, 'baseline');
  for (const mutation of [v => { v.source.sha = '../escape'; }, v => { v.run.id = '../../escape'; },
    v => { v.environment.secret = 'arbitrary'; }, v => { delete v.metrics['launch.empty']; },
    v => { v.metrics['record.populated'].batches[0][0] = -1; }, v => { v.snapshot.policyHash = '0'.repeat(64); }]) {
    const bad = structuredClone(value); mutation(bad);
    await assert.rejects(async () => verifyObservation(h.root, bad));
  }
});

test('append is immutable, replay is a no-op, and the index is deterministic despite completion order', async t => {
  const h = await repository(t);
  const { verifyObservation, appendResults, readHistory } = await import('./benchmark-history.mjs');
  const first = await verifyObservation(h.root, await observation(h));
  const second = await verifyObservation(h.root, await observation(h, '22222222-2222-4222-8222-222222222222'));
  assert.equal(await appendResults(h.root, [second, first]), 2);
  const index = await readFile(join(h.root, 'benchmarks/README.md'), 'utf8');
  assert.equal(await appendResults(h.root, [first, second]), 0);
  assert.equal(await readFile(join(h.root, 'benchmarks/README.md'), 'utf8'), index);
  await h.git('add', '.'); await h.git('commit', '-m', 'benchmark data');
  assert.equal((await readHistory(h.root, 'HEAD')).length, 2);
  const conflicting = structuredClone(first); conflicting.metrics['launch.empty'].batches[0][0] = 900;
  await assert.rejects(appendResults(h.root, [conflicting]), /conflict|immutable/i);
  assert.ok(index.indexOf(first.run.id) < index.indexOf(second.run.id));
});

test('explicit native failures preserve partial samples without becoming baselines', async t => {
  const h = await repository(t);
  const { verifyObservation } = await import('./benchmark-history.mjs');
  const value = await observation(h);
  value.metrics = { 'launch.empty': { batches: [[1000, 1001]] } };
  value.failure = { code: 'measurementFailed' };
  const record = await verifyObservation(h.root, value);
  assert.equal(record.evaluation.outcome, 'error');
  assert.deepEqual(record.metrics['launch.empty'].batches, [[1000, 1001]]);
  value.metrics['launch.empty'].batches[0].push(Infinity);
  await assert.rejects(verifyObservation(h.root, value), /sample/i);
});

test('generated data does not change source identity but policy and mixed/renamed changes do', async t => {
  const h = await repository(t);
  const { sourceTree, isDataOnlyCommit } = await import('./benchmark-history.mjs');
  const original = await sourceTree(h.root, 'HEAD');
  await mkdir(join(h.root, 'benchmarks/results'), { recursive: true });
  await writeFile(join(h.root, 'benchmarks/results/record.json'), '{}');
  await h.git('add', '.'); await h.git('commit', '-m', 'data');
  assert.equal(await sourceTree(h.root, 'HEAD'), original);
  assert.equal(await isDataOnlyCommit(h.root, 'HEAD'), true);
  await h.git('mv', 'app.swift', 'benchmarks/results/moved.swift'); await h.git('commit', '-m', 'mixed');
  assert.equal(await isDataOnlyCommit(h.root, 'HEAD'), false);
  assert.notEqual(await sourceTree(h.root, 'HEAD'), original);
  await writeFile(join(h.root, 'benchmarks/policy.json'), JSON.stringify({ ...policy, absoluteToleranceMS: 200 }));
  await h.git('add', '.'); await h.git('commit', '-m', 'policy');
  assert.equal(await isDataOnlyCommit(h.root, 'HEAD'), false);
});

test('collection uses the frozen policy/history even after later policy or baseline publication', async t => {
  const h = await repository(t);
  const { verifyObservation, appendResults, freezeSnapshot } = await import('./benchmark-history.mjs');
  const base = await verifyObservation(h.root, await observation(h));
  await appendResults(h.root, [base]); await h.git('add', '.'); await h.git('commit', '-m', 'baseline');
  const snapshot = await freezeSnapshot(h.root, h.sha, 'HEAD');
  const candidate = await observation(h, '33333333-3333-4333-8333-333333333333');
  candidate.snapshot = { historySHA: snapshot.historySHA, policyHash: snapshot.policyHash,
    baselinePath: snapshot.candidates[0].path, baselineHash: snapshot.candidates[0].hash };
  candidate.metrics['record.populated'].batches = [Array(10).fill(1500), Array(10).fill(1550)];
  const before = await verifyObservation(h.root, candidate);
  assert.equal(before.evaluation.outcome, 'regression');
  await writeFile(join(h.root, 'benchmarks/policy.json'), JSON.stringify({ ...policy, relativeTolerance: 1 }));
  await h.git('add', '.'); await h.git('commit', '-m', 'new policy');
  assert.deepEqual(await verifyObservation(h.root, candidate), before);
});

test('publication retries a concurrent main update without dropping either result', async t => {
  const h = await repository(t);
  const { publishResults, verifyObservation } = await import('./benchmark-history.mjs');
  const remote = join(h.root, 'remote.git'); await exec('git', ['init', '--bare', remote]);
  await h.git('remote', 'add', 'origin', remote); await h.git('push', '-u', 'origin', 'main');
  const record = await verifyObservation(h.root, await observation(h));
  let injected = false;
  const run = async (exe, args, options) => {
    if (!injected && exe === 'git' && args[0] === 'push' && args.includes('HEAD:refs/heads/main')) {
      injected = true;
      await writeFile(join(h.root, 'another.swift'), 'new app source');
      await h.git('add', 'another.swift'); await h.git('commit', '-m', 'concurrent source'); await h.git('push', 'origin', 'main');
    }
    return (await exec(exe, args, { cwd: options.cwd })).stdout;
  };
  await publishResults(h.root, [record], { run });
  assert.equal(injected, true);
  const checkout = join(h.root, 'check'); await exec('git', ['clone', '--branch', 'main', remote, checkout]);
  assert.equal(await readFile(join(checkout, 'another.swift'), 'utf8'), 'new app source');
  assert.ok((await readFile(join(checkout, 'benchmarks/README.md'), 'utf8')).includes(record.run.id));
});
