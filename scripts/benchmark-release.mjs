import { resolve } from 'node:path';
import { pathToFileURL } from 'node:url';
import { createBenchmarkAPI } from './benchmark-api.mjs';
import { canonicalJSON, ensureFullHistory, readHistory, shaPattern, sourceTree, verifyObservation } from './benchmark-history.mjs';
import { metricIDs } from './benchmark-metrics.mjs';
import { runCommand } from './prepare-release-version.mjs';

const start = '<!-- whim:performance:start -->', end = '<!-- whim:performance:end -->';
const stableTag = /^v?(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)$/;
const labels = ['Launch (empty)', 'Launch (1,000 Notes)', 'Record → capture ready', 'Stop → saved Note', 'Timeline (1,000 Notes)'];
const escape = value => String(value).replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;')
  .replace(/([\\`*_[\]{}|])/g, '\\$1');

function replaceSection(body, content) {
  const starts = body.split(start).length - 1, ends = body.split(end).length - 1;
  const section = `${start}\n${content}\n${end}`;
  if (!starts && !ends) return body + (body ? '\n\n' : '') + section;
  if (starts !== 1 || ends !== 1 || body.indexOf(end) < body.indexOf(start)) throw Error('Malformed performance section markers; release notes were not changed.');
  return body.slice(0, body.indexOf(start)) + section + body.slice(body.indexOf(end) + end.length);
}

function render(repository, source, selected) {
  const base = `https://github.com/${repository}`;
  const title = '### Performance benchmark';
  if (!selected) return `${title}\n\nBenchmark pending for tagged source [${source.slice(0, 7)}](${base}/commit/${source}). [Benchmark history](${base}/blob/main/benchmarks/README.md).`;
  const { record, path, publication, policy } = selected;
  const details = `[Raw result](${base}/blob/${publication}/${path}) · [Cloud run](${record.run.url}) · measured source [${record.source.sha.slice(0, 7)}](${base}/commit/${record.source.sha})`;
  if (record.failure || record.evaluation.outcome === 'error') return `${title}\n\nBenchmark failed; complete timings are unavailable.\n\n${details}`;
  const statuses = { baseline: 'New baseline', pass: 'Passed', regression: 'Regression detected', inconclusive: 'Inconclusive (unstable measurements)' };
  if (!statuses[record.evaluation.outcome]) throw Error('Unknown release benchmark outcome.');
  const rows = metricIDs.map((id, index) => {
    const metric = record.evaluation.metrics[id];
    const change = metric.deltaFraction === null ? 'n/a' : `${metric.deltaFraction >= 0 ? '+' : ''}${(metric.deltaFraction * 100).toFixed(1)}%`;
    return `| ${labels[index]} | ${Math.round(metric.summaries[0].median)} ms | ${change} |`;
  });
  return [title, '', `**${statuses[record.evaluation.outcome]}** · iPhone simulator · ${escape(record.environment.configuration)} · ${policy.samples} samples per batch`,
    `${escape(record.environment.device)} · ${escape(record.environment.runtime)} · ${escape(record.environment.xcode)}`, '',
    '| Operation | Median | Change vs CI baseline |', '| --- | ---: | ---: |', ...rows, '',
    'Changes use this run’s frozen, comparable CI baseline; n/a marks a new series.', '', details].join('\n');
}

async function listReleases(github, repository) {
  const releases = [];
  for (let page = 1; page <= 100; page++) {
    const batch = await github('GET', `/repos/${repository}/releases?per_page=100&page=${page}`);
    if (!Array.isArray(batch)) throw Error('Invalid GitHub release listing.');
    releases.push(...batch);
    if (batch.length < 100) return releases;
  }
  throw Error('Release listing page limit reached.');
}

export async function syncReleaseBenchmarks(root, { repository, github, run = runCommand, log = console.log, dryRun = false } = {}) {
  if (!/^[a-zA-Z0-9][\w.-]*\/[a-zA-Z0-9][\w.-]*$/.test(repository ?? '') || typeof github !== 'function') throw Error('Configure the release benchmark repository and GitHub API.');
  const releases = (await listReleases(github, repository)).filter(release => !release.draft && !release.prerelease
    && stableTag.test(release.tag_name ?? '') && Number.isSafeInteger(release.id) && release.id > 0);
  if (!releases.length) return { updated: 0 };
  const git = async (...args) => (await run('git', args, { cwd: root, capture: true })).trim();
  await ensureFullHistory(root, { run });
  await git('fetch', '--no-tags', 'origin', '+refs/heads/main:refs/remotes/origin/main');
  const history = await git('rev-parse', 'origin/main');
  const records = await readHistory(root, history, { run });
  const tags = new Map((await git('ls-remote', '--refs', '--tags', 'origin')).split('\n').filter(Boolean).map(line => {
    const [sha, ref] = line.split(/\s+/); return [ref.slice('refs/tags/'.length), sha];
  }));
  const trees = new Map();
  const tree = async sha => {
    if (!trees.has(sha)) trees.set(sha, await sourceTree(root, sha, { run }));
    return trees.get(sha);
  };
  let updated = 0;
  for (const release of releases) {
    const object = tags.get(release.tag_name);
    if (!shaPattern.test(object ?? '')) continue;
    await git('fetch', '--no-tags', 'origin', object);
    const source = await git('rev-parse', `${object}^{commit}`);
    const ancestors = (await git('rev-list', '--topo-order', history)).split('\n');
    if (!ancestors.includes(source) || !await git('ls-tree', '--name-only', source, '--', 'benchmarks/policy.json')) continue;
    const targetTree = await tree(source);
    let selected;
    for (const sha of (await git('rev-list', '--topo-order', source)).split('\n')) {
      const candidates = records.filter(({ record }) => record.source.context === 'main' && record.source.sha === sha);
      if (!candidates.length || await tree(sha) !== targetTree) continue;
      const candidate = candidates.sort((a, b) => Date.parse(b.record.run.measuredAt) - Date.parse(a.record.run.measuredAt) || a.path.localeCompare(b.path))[0];
      const { evaluation, ...observation } = candidate.record;
      const verified = await verifyObservation(root, observation, { run, trustedRef: history });
      if (canonicalJSON(verified.evaluation) !== canonicalJSON(evaluation)) throw Error('Stored release benchmark evaluation does not match its frozen evidence.');
      const policy = JSON.parse(await git('show', `${observation.snapshot.historySHA}:benchmarks/policy.json`));
      const publication = await git('log', '-1', '--format=%H', history, '--', candidate.path);
      if (!shaPattern.test(publication)) throw Error('Missing benchmark publication provenance.');
      selected = { ...candidate, record: verified, policy, publication };
      break;
    }
    // Re-read immediately before writing so unrelated edits since the list are retained.
    let current;
    try { current = await github('GET', `/repos/${repository}/releases/${release.id}`); }
    catch (error) { if (error.status === 404) continue; throw error; }
    if (current.id !== release.id || current.tag_name !== release.tag_name || current.draft || current.prerelease) continue;
    const body = current.body ?? '';
    if (typeof body !== 'string') throw Error('Invalid GitHub release body.');
    const next = replaceSection(body, render(repository, source, selected));
    if (next === body) continue;
    const observed = (await git('ls-remote', '--refs', 'origin', `refs/tags/${release.tag_name}`)).split(/\s+/)[0];
    if (observed !== object) throw Error('Release tag changed while preparing its performance summary.');
    if (dryRun) { log(`Would update performance summary for ${release.tag_name}.`); continue; }
    await github('PATCH', `/repos/${repository}/releases/${release.id}`, { body: next });
    updated++;
    log(`Updated performance summary for ${release.tag_name}.`);
  }
  return { updated };
}

if (process.argv[1] && import.meta.url === pathToFileURL(resolve(process.argv[1])).href) {
  try {
    if (process.argv.slice(2).some(argument => argument !== '--dry-run')) throw Error('Usage: node scripts/benchmark-release.mjs [--dry-run]');
    const env = { ...process.env, WHIM_BENCHMARK_GITHUB_TOKEN: process.env.GH_TOKEN ?? process.env.WHIM_BENCHMARK_GITHUB_TOKEN };
    await syncReleaseBenchmarks(process.cwd(), { repository: env.GITHUB_REPOSITORY ?? env.WHIM_BENCHMARK_REPOSITORY,
      github: createBenchmarkAPI({ env }).github, dryRun: process.argv.includes('--dry-run') });
  } catch (error) { console.error(error.message); process.exitCode = 1; }
}
