import assert from 'node:assert/strict';
import { test } from 'node:test';
import { mkdtemp, mkdir, readFile, writeFile, rm } from 'node:fs/promises';
import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import { join } from 'node:path';
import { tmpdir } from 'node:os';

const sha = letter => letter.repeat(40);
const policy = { protocol: 'iphone-ui-v1', fixture: 'notes-1000-v1' };

test('Cloud workflow roles are explicit, and publisher credentials never belong in a measurement checkout', async () => {
  const { cloudBenchmarkRole } = await import('./benchmark-cloud.mjs');
  const config = { WHIM_BENCHMARK_WORKFLOW_ID: 'measurement', WHIM_BENCHMARK_HISTORY_WORKFLOW_ID: 'history' };
  assert.equal(cloudBenchmarkRole({ ...config, CI_WORKFLOW_ID: 'other' }), null);
  assert.equal(cloudBenchmarkRole({ ...config, CI_WORKFLOW_ID: 'measurement', CI_BRANCH: `benchmark-input/main/${sha('a')}` }), 'measure');
  assert.equal(cloudBenchmarkRole({ ...config, CI_WORKFLOW_ID: 'history', CI_BRANCH: 'main' }), 'history');
  assert.throws(() => cloudBenchmarkRole({ ...config, CI_WORKFLOW_ID: 'history', CI_BRANCH: 'feature', CI_PULL_REQUEST_NUMBER: '1' }), /trusted main/i);
  assert.throws(() => cloudBenchmarkRole({ ...config, CI_WORKFLOW_ID: 'measurement', CI_BRANCH: `benchmark-input/main/${sha('a')}`, WHIM_BENCHMARK_GITHUB_TOKEN: 'secret' }), /credential/i);
});

test('baseline-first scheduling measures every main source in order, without canceling pending work', async () => {
  const { planBenchmarkInputs } = await import('./benchmark-cloud.mjs');
  const sources = [{ sha: sha('a'), context: 'main' }, { sha: sha('b'), context: 'main' }, { sha: sha('c'), context: 'pr/7', ancestors: [sha('a')] }];
  assert.deepEqual(planBenchmarkInputs({ sources, records: [], refs: [], policy }), [sources[0]]);
  const pending = [{ ref: `refs/heads/benchmark-input/main/${sha('a')}`, sha: sha('a') }];
  assert.deepEqual(planBenchmarkInputs({ sources, records: [], refs: pending, policy }), []);
  const records = [{ source: sources[0], protocol: policy.protocol, fixture: policy.fixture, evaluation: { outcome: 'baseline' } }];
  assert.deepEqual(planBenchmarkInputs({ sources, records, refs: [], policy }), [sources[1], sources[2]]);
  records.push({ source: sources[1], protocol: policy.protocol, fixture: policy.fixture, evaluation: { outcome: 'regression' } });
  assert.deepEqual(planBenchmarkInputs({ sources, records, refs: [], policy }), [sources[2]]);
});

test('native result attribution checks source, Cloud build identity, and PR/main context independently', async () => {
  const { assertCloudAttribution } = await import('./benchmark-cloud.mjs');
  const id = '11111111-1111-4111-8111-111111111111';
  const build = { id, attributes: { sourceCommit: { commitSha: sha('a') }, number: 3 } };
  const input = { sha: sha('a'), context: 'pr/7' };
  const raw = { source: { sha: sha('a'), context: 'pr/7' }, run: { id, number: 3 } };
  assert.doesNotThrow(() => assertCloudAttribution(raw, build, input));
  assert.throws(() => assertCloudAttribution({ ...raw, source: { sha: sha('b'), context: 'pr/7' } }, build, input), /attribution/i);
  assert.throws(() => assertCloudAttribution({ ...raw, source: { sha: sha('a'), context: 'main' } }, build, input), /attribution/i);
  assert.throws(() => assertCloudAttribution({ ...raw, run: { id: 'other', number: 3 } }, build, input), /attribution/i);
});

test('input refs cannot be moved or recreated over a pending different source', async () => {
  const { ensureInputRef } = await import('./benchmark-cloud.mjs');
  const calls = [];
  const github = async (method, path, body) => {
    calls.push({ method, path, body });
    if (method === 'GET') return { object: { sha: sha('b') } };
    throw Object.assign(Error('already exists'), { status: 422 });
  };
  await assert.rejects(ensureInputRef(github, 'owner/repo', { sha: sha('a'), context: 'main' }), /immutable|different/i);
  assert.ok(!calls.some(call => call.method === 'PATCH' || call.method === 'DELETE'));
  const { planBenchmarkInputs } = await import('./benchmark-cloud.mjs');
  assert.throws(() => planBenchmarkInputs({ sources: [{ sha: sha('a'), context: 'main' }], records: [], policy,
    refs: [{ ref: `refs/heads/benchmark-input/main/${sha('a')}`, sha: sha('b') }] }), /immutable|different/i);
});

test('native artifact export honors the real xcresulttool attachment manifest and rejects path traversal', async t => {
  const { observationFromBundle } = await import('./benchmark-cloud.mjs');
  const root = await mkdtemp(join(tmpdir(), 'whim-benchmark-export-'));
  t.after(() => rm(root, { recursive: true, force: true }));
  const raw = { schemaVersion: 1, marker: 'actual manifest contract' };
  const output = join(root, 'export');
  const calls = [];
  const run = async (exe, args) => {
    calls.push([exe, args]); await mkdir(output, { recursive: true });
    await writeFile(join(output, 'manifest.json'), JSON.stringify([{ testIdentifier: 'WhimPerformanceTests/testBenchmarkOperations()',
      attachments: [{ suggestedHumanReadableName: 'whim-benchmark-observation_0_12BBA5D3-E159-43EE-9DA6-A92B989B389F.json', exportedFileName: 'attachment-123.json' }] }]));
    await writeFile(join(output, 'attachment-123.json'), JSON.stringify(raw));
  };
  assert.deepEqual(await observationFromBundle('/native/result.xcresult', output, { run }), raw);
  assert.deepEqual(calls[0], ['xcrun', ['xcresulttool', 'export', 'attachments', '--path', '/native/result.xcresult', '--output-path', output]]);
  const malicious = async () => writeFile(join(output, 'manifest.json'), JSON.stringify([{ testIdentifier: 'WhimPerformanceTests/testBenchmarkOperations()', attachments: [{
    suggestedHumanReadableName: 'whim-benchmark-observation.json', exportedFileName: '../outside.json' }] }]));
  await assert.rejects(observationFromBundle('/native/result.xcresult', output, { run: malicious }), /unsafe/i);
});

test('native result archives reject symlinks and escaping members before invoking xcresulttool', async t => {
  const { extractNativeObservation } = await import('./benchmark-cloud.mjs');
  const root = await mkdtemp(join(tmpdir(), 'whim-benchmark-archive-'));
  t.after(() => rm(root, { recursive: true, force: true }));
  const exec = promisify(execFile);
  for (const name of ['../escape', '/absolute', 'result.xcresult/symlink']) {
    const archive = join(root, 'native.zip');
    await exec('python3', ['-c', 'import sys,zipfile; z=zipfile.ZipFile(sys.argv[1],"w"); i=zipfile.ZipInfo(sys.argv[2]); i.external_attr=0o120777<<16 if "symlink" in sys.argv[2] else 0; z.writestr(i,"bad"); z.close()', archive, name]);
    const calls = [];
    const run = async (exe, args) => { calls.push(exe); return (await exec(exe, args)).stdout; };
    await assert.rejects(extractNativeObservation(archive, root, { run }), /Unsafe native archive entry/);
    assert.deepEqual(calls, ['python3']);
  }
});

for (const scenario of ['buildFailed', 'invalidArtifact', 'missingArtifact', 'missingRunner']) test(`${scenario} is permanently recorded without fabricated timings and the next source is scheduled`, async t => {
  const { collectBenchmarkHistory } = await import('./benchmark-cloud.mjs');
  const root = await mkdtemp(join(tmpdir(), 'whim-benchmark-collect-'));
  t.after(() => rm(root, { force: true, recursive: true }));
  const exec = promisify(execFile);
  const git = async (...args) => (await exec('git', args, { cwd: root })).stdout.trim();
  await git('init', '-b', 'main'); await git('config', 'user.name', 'Test'); await git('config', 'user.email', 'test@example.com');
  await mkdir(join(root, 'benchmarks'));
  const storedPolicy = await readFile(new URL('../benchmarks/policy.json', import.meta.url), 'utf8');
  await writeFile(join(root, 'benchmarks/policy.json'), storedPolicy); await writeFile(join(root, 'app.swift'), 'initial');
  if (scenario !== 'missingRunner') {
    for (const path of ['ios/whim.xcodeproj/xcshareddata/xcschemes/WhimPerformanceTests.xcscheme', 'e2e/iphone/Performance.e2e.test.swift', 'scripts/benchmark-input.mjs']) {
      await mkdir(join(root, path, '..'), { recursive: true }); await writeFile(join(root, path), 'native runner');
    }
  }
  await git('add', '.'); await git('commit', '-m', 'rollout'); const first = await git('rev-parse', 'HEAD');
  if (scenario === 'missingRunner') {
    for (const path of ['ios/whim.xcodeproj/xcshareddata/xcschemes/WhimPerformanceTests.xcscheme', 'e2e/iphone/Performance.e2e.test.swift', 'scripts/benchmark-input.mjs']) {
      await mkdir(join(root, path, '..'), { recursive: true }); await writeFile(join(root, path), 'native runner');
    }
  }
  await writeFile(join(root, 'app.swift'), 'next'); await git('add', '.'); await git('commit', '-m', 'next'); const second = await git('rev-parse', 'HEAD');
  const remote = join(root, 'remote.git'); await exec('git', ['init', '--bare', '--initial-branch=main', remote]);
  await git('remote', 'add', 'origin', remote); await git('push', '-u', 'origin', 'main');
  const workflow = '11111111-1111-4111-8111-111111111111';
  const buildID = '22222222-2222-4222-8222-222222222222';
  const ref = `refs/heads/benchmark-input/main/${first}`;
  const calls = [];
  const api = {
    github: async (method, path, body) => {
      calls.push({ method, path, body });
      if (path.includes('matching-refs/heads/benchmark-input/')) return [{ ref, object: { sha: first } }];
      if (path.includes('matching-refs/heads/benchmark-queue/')) return [];
      if (path.includes('/pulls?')) return [];
      return {};
    },
    asc: async (method, path) => {
      if (scenario === 'missingRunner' && path.includes('/buildRuns?')) return { data: [] };
      if (path === `/v1/ciBuildRuns/${buildID}`) return { data: { id: buildID, attributes: { number: 7, createdDate: '2026-11-13T13:00:00Z' } } };
      if (path.includes('/buildRuns?')) return { data: [{ id: buildID, attributes: { sourceCommit: { commitSha: first }, number: 7,
        executionProgress: 'COMPLETE', completionStatus: 'FAILED', finishedDate: '2026-11-13T13:00:00Z' },
        relationships: { sourceBranchOrTag: { data: { id: 'reference' } } } }],
        included: [{ id: 'reference', type: 'scmGitReferences', attributes: { canonicalName: ref } }] };
      if (path.includes('/actions?')) return { data: [{ id: 'compile', attributes: { actionType: scenario === 'buildFailed' ? 'BUILD' : 'TEST', completionStatus: 'FAILED' } }] };
      if (path.includes('/artifacts?')) return { data: scenario === 'invalidArtifact' ? [{ attributes: { fileType: 'RESULT_BUNDLE', downloadUrl: 'https://storage.example/native.zip' } }] : [] };
      throw Error(`Unexpected API request ${path}`);
    },
    download: async (url, output) => writeFile(output, 'invalid native archive'),
  };
  const run = async (exe, args, options = {}) => {
    const actual = [...args];
    if (exe === 'git' && actual[0] === 'clone') actual[actual.length - 2] = remote;
    return (await exec(exe, actual, { cwd: options.cwd, env: options.env })).stdout;
  };
  const collection = collectBenchmarkHistory(root, { api, run, log: () => {}, env: { CI_WORKFLOW_ID: 'history', WHIM_BENCHMARK_HISTORY_WORKFLOW_ID: 'history',
    CI_BRANCH: 'main', CI_BUILD_ID: buildID, WHIM_BENCHMARK_REPOSITORY: 'owner/repo', WHIM_BENCHMARK_ROLLOUT_SHA: first,
    WHIM_BENCHMARK_WORKFLOW_ID: workflow, WHIM_BENCHMARK_GITHUB_TOKEN: 'synthetic' } });
  if (scenario === 'buildFailed' || scenario === 'missingRunner') await collection;
  else await assert.rejects(collection);
  const file = (await exec('git', ['--git-dir', remote, 'show', `main:benchmarks/results/${first}/${buildID}.json`])).stdout;
  const record = JSON.parse(file);
  assert.equal(record.evaluation.outcome, 'error'); assert.equal(record.failure.code, scenario); assert.deepEqual(record.metrics, {});
  assert.ok(calls.some(c => c.method === 'POST' && c.body?.sha === second));
  if (scenario !== 'missingRunner') assert.ok(calls.some(c => c.method === 'DELETE' && c.path.endsWith(first)));
  assert.ok(!calls.some(c => c.method === 'POST' && c.body?.sha === first));
});

test('observed PR backlog refs preserve superseded commits without triggering measurements before a baseline', async () => {
  const { preservePRBacklog, planBenchmarkInputs } = await import('./benchmark-cloud.mjs');
  const calls = [];
  const github = async (method, path, body) => { calls.push({ method, path, body }); return {}; };
  const sources = [{ sha: sha('a'), context: 'pr/7' }, { sha: sha('b'), context: 'pr/7' }];
  await preservePRBacklog(github, 'owner/repo', sources, []);
  assert.deepEqual(calls.map(c => c.body.ref), sources.map(s => `refs/heads/benchmark-queue/${s.context}/${s.sha}`));
  assert.deepEqual(planBenchmarkInputs({ sources, records: [], refs: [], policy }), []);
  calls.length = 0;
  await preservePRBacklog(github, 'owner/repo', sources, [{ source: sources[0], protocol: policy.protocol, fixture: policy.fixture }], policy);
  assert.deepEqual(calls.map(c => c.body.sha), [sha('b')]);
});

test('a provisional PR baseline is retried only after compatible main evidence exists', async () => {
  const { planBenchmarkInputs } = await import('./benchmark-cloud.mjs');
  const source = { sha: sha('b'), context: 'pr/7', ancestors: [sha('a')] };
  const record = { source, ...policy, environment: { cpu: 'new host' }, evaluation: { outcome: 'baseline' }, snapshot: { baselinePath: null } };
  const main = { source: { sha: sha('a'), context: 'main' }, ...policy, environment: { cpu: 'old host' }, evaluation: { outcome: 'baseline' } };
  assert.deepEqual(planBenchmarkInputs({ sources: [source], records: [record, main], refs: [], policy }), []);
  main.environment = { cpu: 'new host' };
  assert.deepEqual(planBenchmarkInputs({ sources: [source], records: [record, main], refs: [], policy }), [source]);
});

test('out-of-order Cloud pages retain the newest pending build for each exact input', async () => {
  const { latestInputBuilds } = await import('./benchmark-cloud.mjs');
  const reference = { id: 'ref', type: 'scmGitReferences', attributes: { canonicalName: `refs/heads/benchmark-input/pr/7/${sha('a')}` } };
  const build = number => ({ id: String(number), attributes: { number, sourceCommit: { commitSha: sha('a') }, executionProgress: number === 2 ? 'RUNNING' : 'COMPLETE' }, relationships: { sourceBranchOrTag: { data: { id: 'ref' } } } });
  const latest = latestInputBuilds({ data: [build(2), build(1)], included: [reference] });
  assert.equal([...latest.values()][0].id, '2');
  assert.throws(() => latestInputBuilds({ data: [{ ...build(3), attributes: { number: 3, sourceCommit: { commitSha: sha('b') } } }], included: [reference] }), /attribution|source/i);
});
