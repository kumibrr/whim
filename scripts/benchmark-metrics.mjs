export const metricIDs = Object.freeze(['launch.empty', 'launch.populated', 'record.populated', 'stop.populated', 'timeline.populated']);

export function validatePolicy(policy) {
  if (!policy || policy.schemaVersion !== 1 || !['protocol', 'fixture', 'configuration'].every(k => /^[a-z0-9-]{1,64}$/.test(policy[k] ?? ''))
    || !Number.isInteger(policy.samples) || policy.samples < 3 || policy.samples > 100
    || !Number.isInteger(policy.warmups) || policy.warmups < 0 || policy.warmups > 10
    || !['relativeTolerance', 'absoluteToleranceMS', 'maxMADFraction'].every(k => Number.isFinite(policy[k]) && policy[k] >= 0)
    || policy.relativeTolerance > 1 || policy.maxMADFraction > 1
    || !Number.isInteger(policy.maxRecordBytes) || policy.maxRecordBytes < 1024 || policy.maxRecordBytes > 1048576) {
    throw Error('Invalid benchmark policy.');
  }
  return policy;
}

const median = values => {
  const sorted = [...values].sort((a, b) => a - b);
  const middle = Math.floor(sorted.length / 2);
  return sorted.length % 2 ? sorted[middle] : (sorted[middle - 1] + sorted[middle]) / 2;
};

export function summarize(samples, policy) {
  validatePolicy(policy);
  if (!Array.isArray(samples) || samples.length !== policy.samples || !samples.every(x => Number.isFinite(x) && x >= 0 && x <= 3600000)) {
    throw Error('Expected a complete batch of finite nonnegative millisecond samples.');
  }
  const center = median(samples);
  return { count: samples.length, median: center, min: Math.min(...samples), max: Math.max(...samples), mad: median(samples.map(x => Math.abs(x - center))) };
}

export function evaluateMetric(batches, baseline, policy) {
  if (!Array.isArray(batches) || batches.length < 1 || batches.length > 2) throw Error('Expected one or two sample batches.');
  if (baseline !== null && (!Number.isFinite(baseline) || baseline <= 0)) throw Error('Invalid baseline median.');
  const summaries = batches.map(x => summarize(x, policy));
  const unstable = s => s.median <= 0 || s.mad > s.median * policy.maxMADFraction;
  const slower = s => s.median - baseline > policy.absoluteToleranceMS && s.median > baseline * (1 + policy.relativeTolerance);
  let outcome;
  if (summaries.some(unstable)) outcome = 'inconclusive';
  else if (baseline === null) outcome = 'baseline';
  else if (!slower(summaries[0])) outcome = 'pass';
  else if (summaries.length === 1) outcome = 'confirmationRequired';
  else outcome = slower(summaries[1]) ? 'regression' : 'inconclusive';
  return { outcome, summaries, baseline, deltaMS: baseline === null ? null : summaries[0].median - baseline,
    deltaFraction: baseline === null ? null : summaries[0].median / baseline - 1 };
}

export function evaluateRun(measurements, baseline, policy) {
  if (!measurements || Object.keys(measurements).length !== metricIDs.length || !metricIDs.every(id => Object.hasOwn(measurements, id))) {
    throw Error('Expected every required benchmark metric, with no unknown metrics.');
  }
  const metrics = Object.fromEntries(metricIDs.map(id => {
    const prior = baseline === null ? null : summarize(baseline?.[id]?.batches?.[0], policy).median;
    return [id, evaluateMetric(measurements[id].batches, prior, policy)];
  }));
  const outcomes = Object.values(metrics).map(x => x.outcome === 'confirmationRequired' ? 'error' : x.outcome);
  const outcome = ['error', 'regression', 'inconclusive', 'baseline', 'pass'].find(x => outcomes.includes(x));
  return { outcome, metrics };
}
