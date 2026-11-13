import { sign } from 'node:crypto';
import { createWriteStream } from 'node:fs';
import { Transform } from 'node:stream';
import { pipeline } from 'node:stream/promises';

export function appStoreToken(env, now = Math.floor(Date.now() / 1000)) {
  if (!env.WHIM_ASC_ISSUER_ID || !env.WHIM_ASC_KEY_ID || !env.WHIM_ASC_PRIVATE_KEY) throw Error('Missing App Store Connect API credentials.');
  const encode = value => Buffer.from(JSON.stringify(value)).toString('base64url');
  const header = encode({ alg: 'ES256', kid: env.WHIM_ASC_KEY_ID, typ: 'JWT' });
  const claims = encode({ iss: env.WHIM_ASC_ISSUER_ID, iat: now, exp: now + 600, aud: 'appstoreconnect-v1' });
  const unsigned = `${header}.${claims}`;
  try {
    const signature = sign('sha256', Buffer.from(unsigned), { key: env.WHIM_ASC_PRIVATE_KEY.replaceAll('\\n', '\n'), dsaEncoding: 'ieee-p1363' });
    return `${unsigned}.${signature.toString('base64url')}`;
  } catch { throw Error('Invalid App Store Connect signing credential.'); }
}

export function createBenchmarkAPI({ env = process.env, fetch: request = fetch } = {}) {
  const json = async (origin, token, method, path, body) => {
    const url = new URL(path, origin);
    if (url.origin !== origin || url.username || url.password) throw Error('API URL must remain on its authorized origin.');
    const response = await request(url.href, { method, redirect: 'error', signal: AbortSignal.timeout(60000),
      headers: { Authorization: `Bearer ${token}`, Accept: 'application/json', 'Content-Type': 'application/json' },
      ...(body === undefined ? {} : { body: JSON.stringify(body) }) });
    if (!response.ok) throw Object.assign(Error(`Benchmark API ${method} failed with HTTP ${response.status}.`), { status: response.status });
    if (response.status === 204) return null;
    if (Number(response.headers.get('content-length')) > 4 * 1024 * 1024) throw Error('Oversized API response.');
    const text = await response.text();
    if (Buffer.byteLength(text) > 4 * 1024 * 1024) throw Error('Oversized API response.');
    return JSON.parse(text);
  };
  return {
    github: (method, path, body) => {
      if (!env.WHIM_BENCHMARK_GITHUB_TOKEN) throw Error('Missing benchmark GitHub write credential.');
      return json('https://api.github.com', env.WHIM_BENCHMARK_GITHUB_TOKEN, method, path, body);
    },
    asc: (method, path, body) => json('https://api.appstoreconnect.apple.com', appStoreToken(env), method, path, body),
    download: async (url, output, maxBytes = 256 * 1024 * 1024) => {
      const parsed = new URL(url);
      if (parsed.protocol !== 'https:' || parsed.username || parsed.password) throw Error('Invalid native artifact download URL.');
      // Artifact URLs are signed by Apple. Never forward either API token to a
      // storage/CDN origin, and never print the signed URL in diagnostics.
      const response = await request(parsed.href, { signal: AbortSignal.timeout(120000) });
      if (!response.ok || !response.body) throw Error(`Native artifact download failed (${response.status}).`);
      if (Number(response.headers.get('content-length')) > maxBytes) throw Error('Oversized native result archive.');
      let size = 0;
      const bound = new Transform({ transform(chunk, encoding, callback) {
        size += chunk.length;
        callback(size > maxBytes ? Error('Oversized native result archive.') : null, chunk);
      } });
      await pipeline(response.body, bound, createWriteStream(output, { flags: 'wx', mode: 0o600 }));
    },
  };
}

export async function paginated(request, path, maxPages = 100) {
  const data = [], included = [], seen = new Set();
  let next = path;
  for (let page = 0; next && page < maxPages; page++) {
    if (seen.has(next)) throw Error('Cyclic API pagination.');
    seen.add(next);
    const response = await request('GET', next);
    if (!Array.isArray(response?.data)) throw Error('Invalid paginated API response.');
    data.push(...response.data); included.push(...response.included ?? []);
    next = response.links?.next;
  }
  if (next) throw Error('Benchmark API page limit reached; collection is incomplete.');
  return { data, included };
}
