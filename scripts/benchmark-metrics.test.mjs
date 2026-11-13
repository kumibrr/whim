import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { test } from 'node:test';

const metrics = ['launch.empty', 'launch.populated', 'record.populated', 'stop.populated', 'timeline.populated'];
const policy = { schemaVersion: 1, protocol: 'iphone-ui-v1', fixture: 'notes-1000-v1', configuration: 'optimized-debug', warmups: 2, samples: 10, relativeTolerance: 0.2, absoluteToleranceMS: 100, maxMADFraction: 0.15, maxRecordBytes: 262144 };
const samples = ms => Array(10).fill(ms);

test('a slowdown must exceed BOTH tolerances and be confirmed by a second stable batch', async () => {
  const { evaluateMetric } = await import('./benchmark-metrics.mjs');
  assert.equal(evaluateMetric([samples(1200)], 1000, policy).outcome, 'pass');
  assert.equal(evaluateMetric([samples(180)], 100, policy).outcome, 'pass');
  assert.equal(evaluateMetric([samples(1201)], 1000, policy).outcome, 'confirmationRequired');
  assert.equal(evaluateMetric([samples(1201), samples(1210)], 1000, policy).outcome, 'regression');
  assert.equal(evaluateMetric([samples(1201), samples(1100)], 1000, policy).outcome, 'inconclusive');
  assert.equal(evaluateMetric([samples(1000)], null, policy).outcome, 'baseline');
});

test('sample statistics preserve real spread and reject incomplete or invalid measurements', async () => {
  const { summarize, evaluateMetric } = await import('./benchmark-metrics.mjs');
  assert.deepEqual(summarize([90, 92, 94, 96, 98, 102, 104, 106, 108, 110], policy),
    { count: 10, median: 100, min: 90, max: 110, mad: 6 });
  for (const batch of [[], samples(2).slice(1), samples(-1), samples(NaN), samples(Infinity)]) {
    assert.throws(() => summarize(batch, policy), /sample|finite|negative/i);
  }
  assert.equal(evaluateMetric([[1, 1, 1, 1, 1, 100, 100, 100, 100, 100]], null, policy).outcome, 'inconclusive');
  assert.equal(evaluateMetric([samples(0)], null, policy).outcome, 'inconclusive');
});

test('every required metric is evaluated and missing confirmation fails the complete run', async () => {
  const { evaluateRun } = await import('./benchmark-metrics.mjs');
  const baseline = Object.fromEntries(metrics.map(id => [id, { batches: [samples(1000)] }]));
  const observation = Object.fromEntries(metrics.map(id => [id, { batches: [samples(1000)] }]));
  assert.equal(evaluateRun(observation, baseline, policy).outcome, 'pass');
  assert.equal(evaluateRun(observation, null, policy).outcome, 'baseline');
  observation['record.populated'].batches = [samples(1500)];
  assert.equal(evaluateRun(observation, baseline, policy).outcome, 'error');
  observation['record.populated'].batches.push(samples(1600));
  assert.equal(evaluateRun(observation, baseline, policy).outcome, 'regression');
  delete observation['launch.empty'];
  assert.throws(() => evaluateRun(observation, baseline, policy), /metric/i);
});

test('policy and native/Node conformance cases are reviewed source with exact defaults', async () => {
  const { validatePolicy, evaluateMetric } = await import('./benchmark-metrics.mjs');
  const stored = JSON.parse(await readFile(new URL('../benchmarks/policy.json', import.meta.url)));
  assert.deepEqual(validatePolicy(stored), policy);
  for (const bad of [{ ...policy, samples: 0 }, { ...policy, relativeTolerance: -1 }, { ...policy, maxMADFraction: NaN }]) {
    assert.throws(() => validatePolicy(bad), /policy/i);
  }
  const cases = JSON.parse(await readFile(new URL('../benchmarks/support/comparison-cases.json', import.meta.url)));
  for (const c of cases) {
    const batches = c.values.map(values => values.length === 1 ? samples(values[0]) : values);
    assert.equal(evaluateMetric(batches, c.baseline, policy).outcome, c.expected, c.name);
  }
});
