import assert from 'node:assert/strict';
import { generateKeyPairSync, verify } from 'node:crypto';
import { test } from 'node:test';

test('App Store Connect JWT uses bounded ES256 auth without sending GitHub credentials', async () => {
  const { appStoreToken, createBenchmarkAPI } = await import('./benchmark-api.mjs');
  const { privateKey, publicKey } = generateKeyPairSync('ec', { namedCurve: 'prime256v1' });
  const env = { WHIM_ASC_ISSUER_ID: 'issuer', WHIM_ASC_KEY_ID: 'key',
    WHIM_ASC_PRIVATE_KEY: privateKey.export({ type: 'pkcs8', format: 'pem' }), WHIM_BENCHMARK_GITHUB_TOKEN: 'git-token' };
  const token = appStoreToken(env, 1000);
  const [header, claims, signature] = token.split('.');
  assert.equal(JSON.parse(Buffer.from(header, 'base64url')).alg, 'ES256');
  const payload = JSON.parse(Buffer.from(claims, 'base64url'));
  assert.equal(payload.aud, 'appstoreconnect-v1'); assert.equal(payload.exp - payload.iat, 600);
  assert.ok(verify('sha256', Buffer.from(`${header}.${claims}`), { key: publicKey, dsaEncoding: 'ieee-p1363' }, Buffer.from(signature, 'base64url')));
  const calls = [];
  const api = createBenchmarkAPI({ env, fetch: async (url, options) => {
    calls.push({ url, options }); return new Response(JSON.stringify({ data: [] }), { status: 200 });
  } });
  await api.asc('GET', '/v1/ciBuildRuns'); await api.github('GET', '/repos/owner/repo/pulls');
  assert.ok(calls[0].options.headers.Authorization.startsWith('Bearer '));
  assert.ok(!calls[0].options.headers.Authorization.includes('git-token'));
  assert.equal(calls[1].options.headers.Authorization, 'Bearer git-token');
  await assert.rejects(api.asc('GET', 'https://attacker.invalid/steal'), /origin|URL|host/i);
});

test('API pagination follows same-origin next pages and bounds response errors', async () => {
  const { paginated } = await import('./benchmark-api.mjs');
  const pages = [];
  const result = await paginated(async (method, path) => {
    pages.push(path);
    return pages.length === 1 ? { data: [1], links: { next: 'https://api.appstoreconnect.apple.com/v1/builds?cursor=next' } } : { data: [2], links: { next: null } };
  }, '/v1/builds');
  assert.deepEqual(result.data, [1, 2]);
  assert.equal(pages.length, 2);
});

test('signed native downloads receive no API credentials and enforce streaming byte limits', async t => {
  const { createBenchmarkAPI } = await import('./benchmark-api.mjs');
  const { mkdtemp, readFile, rm } = await import('node:fs/promises');
  const { tmpdir } = await import('node:os');
  const { join } = await import('node:path');
  const root = await mkdtemp(join(tmpdir(), 'whim-download-'));
  t.after(() => rm(root, { recursive: true, force: true }));
  const calls = [];
  const api = createBenchmarkAPI({ env: { WHIM_ASC_PRIVATE_KEY: 'never-forward', WHIM_BENCHMARK_GITHUB_TOKEN: 'never-forward' },
    fetch: async (url, options) => { calls.push(options); return new Response('native zip bytes'); } });
  await api.download('https://storage.example/result.zip?signed=value', join(root, 'good.zip'), 32);
  assert.equal(await readFile(join(root, 'good.zip'), 'utf8'), 'native zip bytes');
  assert.equal(calls[0].headers, undefined);
  await assert.rejects(api.download('https://storage.example/large.zip', join(root, 'large.zip'), 4), /oversized/i);
  await assert.rejects(api.download('http://storage.example/insecure.zip', join(root, 'insecure.zip')), /URL/i);
});
