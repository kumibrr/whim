import { mkdtemp, readFile, readdir, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { createBenchmarkAPI, paginated } from './benchmark-api.mjs';
import { canonicalJSON, ensureFullHistory, freezeSnapshot, isDataOnlyCommit, publishResults, readHistory, shaPattern, uuidPattern, verifyObservation } from './benchmark-history.mjs';
import { runCommand } from './prepare-release-version.mjs';

const secrets = ['WHIM_BENCHMARK_GITHUB_TOKEN', 'WHIM_ASC_PRIVATE_KEY'];
export function cloudBenchmarkRole(env) {
  if (env.WHIM_BENCHMARK_WORKFLOW_ID && env.CI_WORKFLOW_ID === env.WHIM_BENCHMARK_WORKFLOW_ID) {
    if (secrets.some(k => env[k])) throw Error('Publisher credentials must never be supplied to benchmark measurement jobs.');
    if (!/^benchmark-input\/(main|pr\/[1-9]\d*)\/[a-f0-9]{40}$/.test(env.CI_BRANCH ?? '') || env.CI_PULL_REQUEST_NUMBER || env.CI_TAG) throw Error('Invalid benchmark input context.');
    return 'measure';
  }
  if (env.WHIM_BENCHMARK_HISTORY_WORKFLOW_ID && env.CI_WORKFLOW_ID === env.WHIM_BENCHMARK_HISTORY_WORKFLOW_ID) {
    if (env.CI_BRANCH !== 'main' || env.CI_PULL_REQUEST_NUMBER || env.CI_TAG) throw Error('Benchmark publisher requires trusted main.');
    return 'history';
  }
  return null;
}

export function inputRef(source) {
  if (!shaPattern.test(source.sha) || !/^(main|pr\/[1-9]\d*)$/.test(source.context)) throw Error('Invalid benchmark source/context.');
  return `refs/heads/benchmark-input/${source.context}/${source.sha}`;
}

export function planBenchmarkInputs({ sources, records, refs, policy }) {
  for (const ref of refs) {
    const match = /^refs\/heads\/benchmark-input\/(main|pr\/[1-9]\d*)\/([a-f0-9]{40})$/.exec(ref.ref);
    if (!match || match[2] !== ref.sha) throw Error('Immutable benchmark input ref points at a different source.');
  }
  const matching = records.filter(r => r.protocol === policy.protocol && r.fixture === policy.fixture);
  const done = source => {
    const observations = matching.filter(r => r.source.sha === source.sha && r.source.context === source.context);
    if (!observations.length) return false;
    if (source.context === 'main' || observations.some(r => r.snapshot?.baselinePath !== null || r.evaluation.outcome === 'error')) return true;
    return !observations.some(r => matching.some(main => main.source.context === 'main'
      && ['baseline', 'pass'].includes(main.evaluation?.outcome) && source.ancestors?.includes(main.source.sha)
      && canonicalJSON(main.environment) === canonicalJSON(r.environment)));
  };
  const pending = context => refs.some(r => r.ref.startsWith(`refs/heads/benchmark-input/${context}/`));
  const planned = [];
  const contexts = [...new Set(sources.map(s => s.context))];
  for (const context of contexts) {
    if (pending(context)) continue;
    const source = sources.find(s => s.context === context && !done(s));
    if (!source || refs.some(r => r.ref === inputRef(source))) continue;
    if (context !== 'main' && !matching.some(r => r.source.context === 'main' && ['baseline', 'pass'].includes(r.evaluation?.outcome)
      && source.ancestors?.includes(r.source.sha))) continue;
    planned.push(source);
  }
  return planned;
}

export async function preservePRBacklog(github, repository, sources, records, policy) {
  for (const source of sources.filter(s => s.context.startsWith('pr/'))) {
    if (records.some(r => r.source.sha === source.sha && r.source.context === source.context
      && r.protocol === policy?.protocol && r.fixture === policy?.fixture && (r.failure || r.snapshot?.baselinePath !== null))) continue;
    await ensureInputRef(github, repository, source, 'benchmark-queue');
  }
}

export function assertCloudAttribution(raw, build, source) {
  if (raw?.source?.sha !== source.sha || raw.source.context !== source.context
    || build.attributes?.sourceCommit?.commitSha !== source.sha || raw.run?.id?.toLowerCase() !== build.id.toLowerCase()
    || raw.run?.number !== build.attributes.number) throw Error('Native benchmark attribution mismatch.');
}

export function latestInputBuilds(runs) {
  const references = new Map(runs.included.filter(x => x.type === 'scmGitReferences').map(x => [x.id, x]));
  const latest = new Map();
  for (const build of runs.data) {
    const reference = references.get(build.relationships?.sourceBranchOrTag?.data?.id);
    const branch = reference?.attributes?.canonicalName ?? reference?.attributes?.name;
    const match = /^(?:refs\/heads\/)?benchmark-input\/(main|pr\/[1-9]\d*)\/([a-f0-9]{40})$/.exec(branch ?? '');
    if (!match) continue;
    if (build.attributes.sourceCommit?.commitSha !== match[2]) throw Error('Cloud input source attribution mismatch.');
    const ref = inputRef({ context: match[1], sha: match[2] });
    if (!latest.has(ref) || latest.get(ref).attributes.number < build.attributes.number) latest.set(ref, build);
  }
  return latest;
}

export async function ensureInputRef(github, repository, source, prefix = 'benchmark-input') {
  if (!['benchmark-input', 'benchmark-queue'].includes(prefix)) throw Error('Invalid execution ref prefix.');
  const ref = inputRef(source).replace('benchmark-input/', `${prefix}/`);
  try { await github('POST', `/repos/${repository}/git/refs`, { ref, sha: source.sha }); }
  catch (error) {
    if (error.status !== 422 && error.status !== 409) throw error;
    const existing = await github('GET', `/repos/${repository}/git/ref/${ref.slice('refs/'.length)}`);
    if (existing.object?.sha !== source.sha) throw Error('Immutable benchmark input ref points at a different source.');
  }
  return ref;
}

const archiveExtraction = `
import os, pathlib, stat, sys, zipfile
archive, output = sys.argv[1:]
with zipfile.ZipFile(archive) as z:
    entries = z.infolist()
    if len(entries) > 30000 or sum(e.file_size for e in entries) > 512 * 1024 * 1024:
        raise ValueError('Oversized native result archive')
    names = set()
    for entry in entries:
        name = pathlib.PurePosixPath(entry.filename)
        mode = entry.external_attr >> 16
        if name.is_absolute() or '..' in name.parts or '\\\\' in entry.filename or stat.S_ISLNK(mode) or entry.filename in names:
            raise ValueError('Unsafe native archive entry')
        names.add(entry.filename)
    z.extractall(output)
`;

export async function extractNativeObservation(archive, directory, { run = runCommand } = {}) {
  const extracted = join(directory, 'native');
  await run('python3', ['-c', archiveExtraction, archive, extracted], { capture: true });
  const bundles = (await readdir(extracted, { withFileTypes: true })).filter(e => e.isDirectory() && e.name.endsWith('.xcresult'));
  if (bundles.length !== 1) throw Error('Expected exactly one native result bundle.');
  return observationFromBundle(join(extracted, bundles[0].name), join(directory, 'attachments'), { run });
}

export async function observationFromBundle(bundle, output, { run = runCommand } = {}) {
  await run('xcrun', ['xcresulttool', 'export', 'attachments', '--path', bundle, '--output-path', output], { capture: true });
  const manifest = JSON.parse(await readFile(join(output, 'manifest.json'), 'utf8'));
  const files = manifest.filter(test => test.testIdentifier === 'WhimPerformanceTests/testBenchmarkOperations()')
    .flatMap(test => test.attachments ?? []).filter(attachment =>
      /^whim-benchmark-observation(?:_\d+_[a-fA-F0-9]{8}(?:-[a-fA-F0-9]{4}){3}-[a-fA-F0-9]{12})?\.json$/.test(attachment.suggestedHumanReadableName ?? ''));
  if (files.length !== 1) throw Error('Expected one benchmark observation attachment.');
  const name = files[0].exportedFileName;
  if (typeof name !== 'string' || name.includes('/') || name.includes('\\') || name.startsWith('.')) throw Error('Unsafe native attachment filename.');
  const data = await readFile(join(output, name));
  if (data.length > 1048576) throw Error('Oversized benchmark observation.');
  return JSON.parse(data);
}

async function githubList(github, path) {
  const values = [];
  for (let page = 1; page <= 100; page++) {
    const result = await github('GET', `${path}${path.includes('?') ? '&' : '?'}per_page=100&page=${page}`);
    if (!Array.isArray(result)) throw Error('Invalid GitHub list response.');
    values.push(...result);
    if (result.length < 100) return values;
  }
  throw Error('GitHub discovery page limit reached.');
}

export async function collectBenchmarkHistory(root, { env = process.env, run = runCommand, api = createBenchmarkAPI({ env }), log = console.log } = {}) {
  if (cloudBenchmarkRole(env) !== 'history') throw Error('Collection requires the trusted history workflow.');
  const repository = env.WHIM_BENCHMARK_REPOSITORY;
  const rollout = env.WHIM_BENCHMARK_ROLLOUT_SHA;
  if (!/^[a-zA-Z0-9][\w.-]*\/[a-zA-Z0-9][\w.-]*$/.test(repository ?? '') || !shaPattern.test(rollout ?? '')
    || !uuidPattern.test(env.WHIM_BENCHMARK_WORKFLOW_ID ?? '')) throw Error('Configure benchmark repository, rollout SHA and workflow ID.');
  const token = env.WHIM_BENCHMARK_GITHUB_TOKEN;
  if (!token) throw Error('Missing benchmark GitHub write credential.');
  const authorizedRun = (exe, args, options = {}) => run(exe, args, { ...options, env: { ...process.env,
    GIT_TERMINAL_PROMPT: '0', GIT_CONFIG_COUNT: '1', GIT_CONFIG_KEY_0: 'http.https://github.com/.extraheader',
    GIT_CONFIG_VALUE_0: 'Authorization: Basic ' + Buffer.from('x-access-token:' + token).toString('base64') } });
  const git = async (...args) => (await authorizedRun('git', args, { cwd: root, capture: true })).trim();
  await ensureFullHistory(root, { run: authorizedRun });
  await git('fetch', '--no-tags', 'origin', '+refs/heads/main:refs/remotes/origin/main');
  await git('merge-base', '--is-ancestor', rollout, 'origin/main');
  const policy = JSON.parse(await git('show', 'origin/main:benchmarks/policy.json'));
  const existing = (await readHistory(root, 'origin/main', { run: authorizedRun })).map(x => x.record);
  const refs = await githubList(api.github, `/repos/${repository}/git/matching-refs/heads/benchmark-input/`);
  const backlog = await githubList(api.github, `/repos/${repository}/git/matching-refs/heads/benchmark-queue/`);
  const runs = await paginated(api.asc, `/v1/ciWorkflows/${env.WHIM_BENCHMARK_WORKFLOW_ID}/buildRuns?limit=200&include=sourceBranchOrTag`);
  const latest = latestInputBuilds(runs);
  const references = new Map(runs.included.filter(x => x.type === 'scmGitReferences').map(x => [x.id, x]));
  const collected = [];
  const completedRefs = new Set();
  const failures = [];
  const recordFailure = async (source, build, code) => {
    // No native decision exists for a build/collection failure. Anchor this
    // explicitly labeled error to the immutable rollout policy, not the moving
    // collector HEAD, so retries cannot mutate an already published record.
    const frozen = await freezeSnapshot(root, source.sha, rollout, { run: authorizedRun });
    const raw = { schemaVersion: 1, protocol: frozen.policy.protocol, fixture: frozen.policy.fixture,
      source: { sha: source.sha, context: source.context, parents: (await git('show', '-s', '--format=%P', source.sha)).split(' ').filter(Boolean),
        committedAt: await git('show', '-s', '--format=%cI', source.sha) },
      run: { id: build.id, number: build.attributes.number,
        url: `https://api.appstoreconnect.apple.com/v1/ciBuildRuns/${build.id}`,
        measuredAt: build.attributes.finishedDate ?? build.attributes.createdDate },
      environment: { architecture: 'unavailable', cpu: 'unavailable', macOS: 'unavailable', kernel: 'unavailable',
        xcode: 'unavailable', runtime: 'unavailable', device: 'unavailable', configuration: frozen.policy.configuration },
      snapshot: { historySHA: frozen.historySHA, policyHash: frozen.policyHash, baselinePath: null, baselineHash: null },
      metrics: {}, failure: { code } };
    return verifyObservation(root, raw, { run: authorizedRun, trustedRef: 'origin/main' });
  };
  for (const build of runs.data) {
    if (build.attributes.executionProgress !== 'COMPLETE') continue;
    const reference = references.get(build.relationships?.sourceBranchOrTag?.data?.id);
    const branch = reference?.attributes?.canonicalName ?? reference?.attributes?.name;
    const match = /^(?:refs\/heads\/)?benchmark-input\/(main|pr\/[1-9]\d*)\/([a-f0-9]{40})$/.exec(branch ?? '');
    if (!match || build.attributes.sourceCommit?.commitSha !== match[2]) continue;
    const source = { context: match[1], sha: match[2] };
    if (existing.some(r => r.run.id.toLowerCase() === build.id.toLowerCase() && r.source.sha === source.sha)) {
      completedRefs.add(inputRef(source)); continue;
    }
    const directory = await mkdtemp(join(tmpdir(), 'whim-cloud-benchmark-'));
    let validatingArtifact = false;
    try {
      if (!uuidPattern.test(build.id)) throw Error('Invalid Cloud build identity.');
      await git('fetch', '--no-tags', 'origin', source.sha);
      const actions = await paginated(api.asc, `/v1/ciBuildRuns/${build.id}/actions?limit=200`);
      const artifacts = [];
      for (const action of actions.data.filter(x => x.attributes.actionType === 'TEST')) {
        artifacts.push(...(await paginated(api.asc, `/v1/ciBuildActions/${action.id}/artifacts?limit=200`)).data);
      }
      const results = artifacts.filter(x => x.attributes.fileType === 'RESULT_BUNDLE');
      if (results.length !== 1) {
        if (results.length === 0 && actions.data.some(a => a.attributes.actionType !== 'TEST' && a.attributes.completionStatus === 'FAILED')) {
          collected.push(await recordFailure(source, build, 'buildFailed')); completedRefs.add(inputRef(source)); continue;
        }
        const age = Date.now() - Date.parse(build.attributes.finishedDate);
        if (results.length === 0 && Number.isFinite(age) && age > 60 * 60 * 1000) {
          collected.push(await recordFailure(source, build, 'missingArtifact')); completedRefs.add(inputRef(source));
        }
        throw Error('Missing/ambiguous native result artifact; queued for retry or explicitly recorded as missing.');
      }
      const archive = join(directory, 'native.zip');
      await api.download(results[0].attributes.downloadUrl, archive);
      validatingArtifact = true;
      const raw = await extractNativeObservation(archive, directory, { run: authorizedRun });
      assertCloudAttribution(raw, build, source);
      const record = await verifyObservation(root, raw, { run: authorizedRun, trustedRef: 'origin/main' });
      collected.push(record); completedRefs.add(inputRef(source));
    } catch (error) {
      if (validatingArtifact) {
        collected.push(await recordFailure(source, build, 'invalidArtifact'));
        completedRefs.add(inputRef(source));
      }
      failures.push(`${source.sha.slice(0, 7)} ${build.id}: ${error.message}`);
    } finally { await rm(directory, { recursive: true, force: true }); }
  }
  // Publish successful collections even when another artifact is unavailable.
  // Fail visibly afterward and revisit the unfinished native runs next sweep.
  const records = [...existing, ...collected];
  const sources = [];
  const mainSHAs = [rollout, ...(await git('rev-list', '--reverse', '--topo-order', `${rollout}..origin/main`)).split('\n').filter(Boolean)];
  for (const sha of mainSHAs) if (!await isDataOnlyCommit(root, sha, { run: authorizedRun })) sources.push({ sha, context: 'main' });
  for (const ref of backlog) {
    const match = /^refs\/heads\/benchmark-queue\/(pr\/[1-9]\d*)\/([a-f0-9]{40})$/.exec(ref.ref);
    if (!match || ref.object?.sha !== match[2]) throw Error('Immutable PR backlog source mismatch.');
    await git('fetch', '--no-tags', 'origin', match[2]);
    sources.push({ sha: match[2], context: match[1], ancestors: (await git('rev-list', match[2])).split('\n') });
  }
  const pulls = await githubList(api.github, `/repos/${repository}/pulls?state=open&base=main`);
  for (const pull of pulls) {
    if (!Number.isSafeInteger(pull.number) || pull.number <= 0 || !shaPattern.test(pull.head?.sha ?? '') || !shaPattern.test(pull.base?.sha ?? '')) throw Error('Invalid PR discovery metadata.');
    await git('fetch', '--no-tags', 'origin', `refs/pull/${pull.number}/head`);
    const head = await git('rev-parse', 'FETCH_HEAD');
    if (head !== pull.head.sha) { failures.push(`PR ${pull.number} changed during discovery; retry next sweep.`); continue; }
    const shas = (await git('rev-list', '--reverse', '--topo-order', `${pull.base.sha}..${head}`)).split('\n').filter(Boolean);
    for (const sha of shas) {
      if (await isDataOnlyCommit(root, sha, { run: authorizedRun })) continue;
      sources.push({ sha, context: `pr/${pull.number}`, ancestors: (await git('rev-list', sha)).split('\n') });
    }
  }
  const uniqueSources = [...new Map(sources.map(s => [`${s.context}/${s.sha}`, s])).values()];
  sources.length = 0;
  sources.push(...uniqueSources.filter(s => s.context === 'main'),
    ...uniqueSources.filter(s => s.context !== 'main').sort((a, b) => a.ancestors.length - b.ancestors.length));
  await preservePRBacklog(api.github, repository, sources.filter(s => !backlog.some(r => r.ref === inputRef(s).replace('benchmark-input/', 'benchmark-queue/'))), records, policy);
  let collectorBuild;
  for (const source of sources) {
    if (records.some(r => r.source.sha === source.sha && r.source.context === source.context
      && r.protocol === policy.protocol && r.fixture === policy.fixture)) continue;
    let available = true;
    for (const path of ['ios/whim.xcodeproj/xcshareddata/xcschemes/WhimPerformanceTests.xcscheme',
      'e2e/iphone/Performance.e2e.test.swift', 'scripts/benchmark-input.mjs']) {
      try { await git('cat-file', '-e', `${source.sha}:${path}`); }
      catch { available = false; break; }
    }
    if (available) continue;
    if (!uuidPattern.test(env.CI_BUILD_ID ?? '')) throw Error('Missing collector build identity for coverage gap.');
    collectorBuild ??= (await api.asc('GET', `/v1/ciBuildRuns/${env.CI_BUILD_ID}`)).data;
    if (collectorBuild?.id !== env.CI_BUILD_ID) throw Error('Collector build identity mismatch.');
    const record = await recordFailure(source, collectorBuild, 'missingRunner');
    collected.push(record); records.push(record); completedRefs.add(inputRef(source));
    log(`Recorded missing benchmark runner for ${source.context} source ${source.sha}.`);
  }
  // Only create new work after its prerequisite records have reached main.
  if (collected.length) await publishResults(root, collected, { run: authorizedRun, remoteURL: `https://github.com/${repository}.git` });
  for (const ref of refs) {
    const build = latest.get(ref.ref);
    const record = build && records.find(r => r.run.id.toLowerCase() === build.id.toLowerCase() && inputRef(r.source) === ref.ref);
    if (!build && completedRefs.has(ref.ref)) continue; // Explicit missing-runner coverage record.
    if (!build) { completedRefs.delete(ref.ref); failures.push(`No native Cloud run observed for ${ref.ref}; check the Benchmark start condition or start it manually.`); continue; }
    if (build.attributes.executionProgress !== 'COMPLETE' || !record) { completedRefs.delete(ref.ref); continue; }
    if (record.source.context.startsWith('pr/') && record.snapshot.baselinePath === null && !record.failure) {
      completedRefs.delete(ref.ref);
      const source = sources.find(s => inputRef(s) === ref.ref);
      const seed = source && records.some(main => main.source.context === 'main' && ['baseline', 'pass'].includes(main.evaluation.outcome)
        && source.ancestors.includes(main.source.sha) && canonicalJSON(main.environment) === canonicalJSON(record.environment));
      if (seed) {
        await api.asc('POST', '/v1/ciBuildRuns', { data: { type: 'ciBuildRuns', relationships: {
          workflow: { data: { type: 'ciWorkflows', id: env.WHIM_BENCHMARK_WORKFLOW_ID } },
          sourceBranchOrTag: { data: build.relationships.sourceBranchOrTag.data },
        } } });
        log(`Requeued provisional PR observation ${record.source.sha} against its newly available main baseline.`);
      } else failures.push(`PR ${record.source.sha} has no compatible main baseline; retain its input and seed the configured main environment.`);
    }
  }
  const pending = refs.filter(r => !completedRefs.has(r.ref)).map(r => ({ ref: r.ref, sha: r.object.sha }));
  for (const source of planBenchmarkInputs({ sources, records, refs: pending, policy })) {
    await ensureInputRef(api.github, repository, source);
    log(`Queued ${source.context} source ${source.sha}.`);
  }
  for (const ref of refs.filter(r => completedRefs.has(r.ref))) {
    await api.github('DELETE', `/repos/${repository}/git/refs/${ref.ref.slice('refs/'.length)}`);
  }
  for (const ref of backlog) {
    if (records.some(r => r.source.context.startsWith('pr/') && inputRef(r.source).replace('benchmark-input/', 'benchmark-queue/') === ref.ref
      && r.protocol === policy.protocol && r.fixture === policy.fixture && (r.failure || r.snapshot.baselinePath !== null))) await api.github('DELETE', `/repos/${repository}/git/refs/${ref.ref.slice('refs/'.length)}`);
  }
  log(`Collected ${collected.length} benchmark run(s); ${failures.length} collection issue(s).`);
  if (failures.length) throw Error(failures.join('\n'));
  return { collected: collected.length };
}

if (process.argv[1] && import.meta.url === pathToFileURL(resolve(process.argv[1])).href) {
  try {
    if (process.argv[2] === 'role') console.log(cloudBenchmarkRole(process.env) ?? 'functional');
    else if (process.argv[2] === 'verify-native') {
      if (!process.argv[3]) throw Error('Provide the native result bundle path.');
      const directory = await mkdtemp(join(tmpdir(), 'whim-native-benchmark-verify-'));
      try {
        const root = fileURLToPath(new URL('..', import.meta.url));
        const raw = await observationFromBundle(process.argv[3], directory);
        const record = await verifyObservation(root, raw);
        console.log(`Native benchmark observation verified: ${record.evaluation.outcome}; source ${record.source.sha}.`);
        if (!['pass', 'baseline'].includes(record.evaluation.outcome)) process.exitCode = 1;
      } finally { await rm(directory, { force: true, recursive: true }); }
    }
    else await collectBenchmarkHistory(process.env.CI_PRIMARY_REPOSITORY_PATH);
  }
  catch (error) { console.error(error.message); process.exitCode = 1; }
}
