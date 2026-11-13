import { createHash } from 'node:crypto';
import { lstat, mkdir, mkdtemp, readFile, readdir, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { runCommand } from './prepare-release-version.mjs';
import { evaluateRun, metricIDs, validatePolicy } from './benchmark-metrics.mjs';

export const shaPattern = /^[a-f0-9]{40}$/;
export const uuidPattern = /^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$/i;
const resultPathPattern = /^benchmarks\/results\/[a-f0-9]{40}\/[a-f0-9-]{36}\.json$/;
const environmentKeys = ['architecture', 'cpu', 'macOS', 'kernel', 'xcode', 'runtime', 'device', 'configuration'];
const gitAt = (root, run = runCommand) => async (...args) => (await run('git', args, { cwd: root, capture: true })).trimEnd();
const sorted = value => Array.isArray(value) ? value.map(sorted) : value && typeof value === 'object'
  ? Object.fromEntries(Object.keys(value).sort().map(k => [k, sorted(value[k])])) : value;
export const canonicalJSON = value => JSON.stringify(sorted(value), null, 2) + '\n';
export const contentHash = value => createHash('sha256').update(canonicalJSON(value)).digest('hex');
export const isBenchmarkData = path => path === 'benchmarks/README.md' || path.startsWith('benchmarks/results/');
export const resultPath = record => {
  if (!shaPattern.test(record?.source?.sha ?? '') || !uuidPattern.test(record?.run?.id ?? '')) throw Error('Invalid result identity.');
  return `benchmarks/results/${record.source.sha}/${record.run.id.toLowerCase()}.json`;
};
const exactKeys = (value, keys) => value && typeof value === 'object' && !Array.isArray(value) && Object.keys(value).length === keys.length && keys.every(k => Object.hasOwn(value, k));
const boundedText = value => typeof value === 'string' && value.length > 0 && value.length <= 180 && !/[\x00-\x1f]/.test(value);

export function validateObservation(value, policy) {
  validatePolicy(policy);
  const failure = Object.hasOwn(value ?? {}, 'failure');
  const keys = ['schemaVersion', 'protocol', 'fixture', 'source', 'run', 'environment', 'snapshot', 'metrics'];
  if (failure) keys.push('failure');
  if (Buffer.byteLength(JSON.stringify(value)) > policy.maxRecordBytes
    || !exactKeys(value, keys)
    || value.schemaVersion !== 1 || value.protocol !== policy.protocol || value.fixture !== policy.fixture
    || !exactKeys(value.source, ['sha', 'parents', 'context', 'committedAt']) || !shaPattern.test(value.source.sha)
    || !Array.isArray(value.source.parents) || value.source.parents.length > 16 || !value.source.parents.every(x => shaPattern.test(x))
    || !/^(main|local|pr\/[1-9]\d*)$/.test(value.source.context) || !Number.isFinite(Date.parse(value.source.committedAt))
    || !exactKeys(value.run, ['id', 'number', 'url', 'measuredAt']) || !uuidPattern.test(value.run.id)
    || !Number.isInteger(value.run.number) || value.run.number < 0 || !Number.isFinite(Date.parse(value.run.measuredAt))
    || !(value.source.context === 'local' && value.run.url === 'local' || /^https:\/\/appstoreconnect\.apple\.com\/[a-zA-Z0-9/_-]+$/.test(value.run.url)
      || /^https:\/\/api\.appstoreconnect\.apple\.com\/v1\/ciBuildRuns\/[a-f0-9-]{36}$/i.test(value.run.url))
    || !exactKeys(value.environment, environmentKeys) || !environmentKeys.every(k => boundedText(value.environment[k]))
    || value.environment.configuration !== policy.configuration
    || !exactKeys(value.snapshot, ['historySHA', 'policyHash', 'baselinePath', 'baselineHash']) || !shaPattern.test(value.snapshot.historySHA)
    || !/^[a-f0-9]{64}$/.test(value.snapshot.policyHash)
    || !((value.snapshot.baselinePath === null && value.snapshot.baselineHash === null)
      || (resultPathPattern.test(value.snapshot.baselinePath) && /^[a-f0-9]{64}$/.test(value.snapshot.baselineHash)))) {
    throw Error('Invalid benchmark observation schema or provenance.');
  }
  if (failure) {
    if (!exactKeys(value.failure, ['code']) || !['measurementFailed', 'baselineUnavailable', 'buildFailed', 'missingArtifact', 'invalidArtifact', 'missingRunner'].includes(value.failure.code)) throw Error('Invalid benchmark failure code.');
    if (!value.metrics || typeof value.metrics !== 'object' || Array.isArray(value.metrics)) throw Error('Invalid partial metrics.');
    for (const [id, metric] of Object.entries(value.metrics)) {
      if (!metricIDs.includes(id) || !exactKeys(metric, ['batches']) || !Array.isArray(metric.batches) || metric.batches.length > 2
        || !metric.batches.every(batch => Array.isArray(batch) && batch.length <= policy.samples && batch.every(x => Number.isFinite(x) && x >= 0 && x <= 3600000))) throw Error('Invalid partial metric samples.');
    }
  } else {
    if (environmentKeys.some(k => ['pending', 'unavailable'].includes(value.environment[k]))) throw Error('Incomplete benchmark environment metadata.');
    for (const id of metricIDs) {
      if (!exactKeys(value.metrics?.[id], ['batches'])) throw Error('Invalid benchmark metric.');
    }
    evaluateRun(value.metrics, null, policy);
  }
  return value;
}

export async function sourceTree(root, ref, { run = runCommand } = {}) {
  const tree = await gitAt(root, run)('ls-tree', '-rz', '--full-tree', ref);
  return createHash('sha256').update(tree.split('\0').filter(line => line && !isBenchmarkData(line.slice(line.indexOf('\t') + 1))).join('\0')).digest('hex');
}

export async function isDataOnlyCommit(root, ref, { run = runCommand } = {}) {
  const files = (await gitAt(root, run)('diff-tree', '--root', '-m', '--no-commit-id', '--name-only', '--no-renames', '-r', '-z', ref)).split('\0').filter(Boolean);
  return files.length > 0 && files.every(isBenchmarkData);
}

export async function readHistory(root, ref = 'HEAD', { run = runCommand } = {}) {
  const git = gitAt(root, run);
  const tree = (await git('ls-tree', '-rz', ref, '--', 'benchmarks/results')).split('\0').filter(Boolean);
  const records = [];
  for (const line of tree) {
    const [entry, path] = line.split('\t');
    if (!resultPathPattern.test(path) || !entry.startsWith('100644 blob ')) throw Error(`Invalid history entry: ${path}`);
    const text = await git('show', `${ref}:${path}`);
    if (Buffer.byteLength(text) > 1048576) throw Error('Oversized history record.');
    const record = JSON.parse(text);
    if (resultPath(record) !== path) throw Error('History record identity mismatch.');
    records.push({ path, hash: contentHash(record), record });
  }
  return records;
}

export async function ensureFullHistory(root, { run = runCommand } = {}) {
  const git = gitAt(root, run);
  if (await git('rev-parse', '--is-shallow-repository') === 'true') await git('fetch', '--unshallow', '--no-tags', 'origin');
}

export async function freezeSnapshot(root, source, historyRef = 'origin/main', { run = runCommand } = {}) {
  if (!shaPattern.test(source)) throw Error('Invalid source SHA.');
  const git = gitAt(root, run);
  const historySHA = await git('rev-parse', `${historyRef}^{commit}`);
  const policy = validatePolicy(JSON.parse(await git('show', `${historySHA}:benchmarks/policy.json`)));
  const ancestors = (await git('rev-list', '--topo-order', source)).split('\n');
  const ranks = new Map(ancestors.map((sha, index) => [sha, index]));
  const records = await readHistory(root, historySHA, { run });
  const mainAncestors = new Set((await git('rev-list', historySHA)).split('\n'));
  const candidates = records.filter(({ record: r }) => {
    if (r.source.context !== 'main' || !ranks.has(r.source.sha) || !mainAncestors.has(r.source.sha)
      || r.protocol !== policy.protocol || r.fixture !== policy.fixture || !['baseline', 'pass'].includes(r.evaluation?.outcome) || r.failure) return false;
    try {
      const { evaluation, ...observation } = r;
      validateObservation(observation, policy);
      return evaluateRun(r.metrics, null, policy).outcome === 'baseline';
    } catch { return false; }
  })
    .sort((a, b) => ranks.get(a.record.source.sha) - ranks.get(b.record.source.sha)
      || b.record.run.measuredAt.localeCompare(a.record.run.measuredAt) || a.path.localeCompare(b.path));
  // Keep one nearest ancestor per environment; this is complete for the decision,
  // unlike truncating the first N runs, which can hide a compatible older host.
  const seen = new Set();
  return { historySHA, policyHash: contentHash(policy), policy, candidates: candidates.filter(({ record }) => {
    const key = canonicalJSON(record.environment);
    if (seen.has(key)) return false;
    seen.add(key); return true;
  }) };
}

export async function verifyObservation(root, observation, { run = runCommand, trustedRef = 'HEAD' } = {}) {
  const git = gitAt(root, run);
  if (!shaPattern.test(observation?.snapshot?.historySHA ?? '') || !shaPattern.test(observation?.source?.sha ?? '')) throw Error('Invalid snapshot/source SHA.');
  await git('merge-base', '--is-ancestor', observation.snapshot.historySHA, trustedRef);
  const frozen = await freezeSnapshot(root, observation.source.sha, observation.snapshot.historySHA, { run });
  const policy = frozen.policy;
  validateObservation(observation, policy);
  if (contentHash(policy) !== observation.snapshot.policyHash) throw Error('Frozen policy hash mismatch.');
  const parents = (await git('show', '-s', '--format=%P', observation.source.sha)).split(' ').filter(Boolean);
  const committedAt = await git('show', '-s', '--format=%cI', observation.source.sha);
  if (canonicalJSON(parents) !== canonicalJSON(observation.source.parents) || committedAt !== observation.source.committedAt) throw Error('Source commit metadata mismatch.');
  if (observation.source.context === 'main') await git('merge-base', '--is-ancestor', observation.source.sha, trustedRef);
  const baseline = frozen.candidates.find(({ record }) => canonicalJSON(record.environment) === canonicalJSON(observation.environment));
  if ((baseline?.path ?? null) !== observation.snapshot.baselinePath || (baseline?.hash ?? null) !== observation.snapshot.baselineHash) {
    throw Error('Frozen baseline identity or hash mismatch.');
  }
  const evaluation = observation.failure ? { outcome: 'error', metrics: {} } : evaluateRun(observation.metrics, baseline?.record.metrics ?? null, policy);
  if (!observation.failure && observation.source.context.startsWith('pr/') && !baseline && evaluation.outcome === 'baseline') evaluation.outcome = 'inconclusive';
  return { ...observation, evaluation };
}

async function workingHistory(root) {
  const records = [];
  const directory = join(root, 'benchmarks/results');
  for (const entry of await readdir(directory, { withFileTypes: true }).catch(e => { if (e.code === 'ENOENT') return []; throw e; })) {
    if (!entry.isDirectory() || !shaPattern.test(entry.name)) throw Error('Invalid history directory.');
    for (const file of await readdir(join(directory, entry.name), { withFileTypes: true })) {
      if (!file.isFile() || !uuidPattern.test(file.name.replace(/\.json$/, ''))) throw Error('Invalid history record path.');
      const path = `benchmarks/results/${entry.name}/${file.name}`;
      const record = JSON.parse(await readFile(join(root, path), 'utf8'));
      if (resultPath(record) !== path) throw Error('History record identity mismatch.');
      records.push(record);
    }
  }
  return records;
}

export function historyIndex(records, { repositoryURL = null } = {}) {
  if (repositoryURL !== null && !/^https:\/\/github\.com\/[a-zA-Z0-9][\w.-]*\/[a-zA-Z0-9][\w.-]*$/.test(repositoryURL)) throw Error('Invalid history repository URL.');
  const rows = [...records].sort((a, b) => Date.parse(a.source.committedAt) - Date.parse(b.source.committedAt)
    || a.source.sha.localeCompare(b.source.sha) || Date.parse(a.run.measuredAt) - Date.parse(b.run.measuredAt) || a.run.id.localeCompare(b.run.id));
  return '# iPhone performance benchmark history\n\nGenerated from immutable simulator observations. Times are medians in milliseconds; fixture capture does not measure physical microphone onset. Generated-data-only commits are excluded to avoid recursively benchmarking history updates.\n\n'
    + '| Source | Context | Run | Launch empty | Launch 1,000 | Record | Stop/save | History | Outcome | Baseline |\n'
    + '| --- | --- | --- | ---: | ---: | ---: | ---: | ---: | --- | --- |\n'
    + rows.map(r => `| ${repositoryURL ? `[${r.source.sha.slice(0, 7)}](${repositoryURL}/commit/${r.source.sha})` : r.source.sha.slice(0, 7)} | ${r.source.context} | ${r.run.url === 'local' ? r.run.id : `[${r.run.id}](${r.run.url})`} | `
      + metricIDs.map(id => r.evaluation?.metrics?.[id]?.summaries?.[0]?.median?.toFixed(2) ?? 'n/a').join(' | ')
      + ` | ${r.evaluation.outcome} | ${r.snapshot.baselinePath?.split('/')[2]?.slice(0, 7) ?? 'new series'} |`).join('\n') + '\n';
}

export async function appendResults(root, records, { repositoryURL = null } = {}) {
  let written = 0;
  for (const record of records) {
    const path = join(root, resultPath(record));
    await mkdir(join(root, 'benchmarks/results', record.source.sha), { recursive: true });
    const bytes = canonicalJSON(record);
    try { await writeFile(path, bytes, { flag: 'wx' }); written++; }
    catch (error) {
      if (error.code !== 'EEXIST') throw error;
      if (!(await lstat(path)).isFile() || await readFile(path, 'utf8') !== bytes) throw Error('Immutable benchmark result conflict.');
    }
  }
  const all = await workingHistory(root);
  await mkdir(join(root, 'benchmarks'), { recursive: true });
  await writeFile(join(root, 'benchmarks/README.md'), historyIndex(all, { repositoryURL }));
  return written;
}

export async function publishResults(root, records, { run = runCommand, attempts = 3, remoteURL } = {}) {
  const directory = await mkdtemp(join(tmpdir(), 'whim-benchmark-publish-'));
  const git = gitAt(root, run);
  const remote = remoteURL ?? await git('remote', 'get-url', 'origin');
  const github = /^https:\/\/github\.com\/([a-zA-Z0-9][\w.-]*\/[a-zA-Z0-9][\w.-]*?)(?:\.git)?$/.exec(remote);
  try {
    for (let attempt = 0; attempt < attempts; attempt++) {
      const checkout = join(directory, `attempt-${attempt}`);
      await run('git', ['clone', '--quiet', '--no-tags', '--branch', 'main', remote, checkout], { cwd: root, capture: true });
      if (await appendResults(checkout, records, { repositoryURL: github ? `https://github.com/${github[1]}` : null }) === 0) return { published: false };
      const local = gitAt(checkout, run);
      await local('add', '--', 'benchmarks/results', 'benchmarks/README.md');
      await local('-c', 'user.name=Whim benchmarks', '-c', 'user.email=benchmarks@users.noreply.github.com', 'commit', '--quiet', '-m', 'chore: record performance benchmarks');
      try {
        await local('push', 'origin', 'HEAD:refs/heads/main');
        return { published: true };
      } catch (error) {
        // Only retry a genuine intervening main update. Authentication and branch
        // protection failures must remain visible rather than being swallowed.
        const head = await local('rev-parse', 'HEAD^');
        const current = (await local('ls-remote', 'origin', 'refs/heads/main')).split(/\s/)[0];
        if (current === head || attempt === attempts - 1) throw error;
      }
    }
  } finally { await rm(directory, { recursive: true, force: true }); }
}
