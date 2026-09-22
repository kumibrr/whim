import assert from 'node:assert/strict';
import { createHash, createHmac, randomUUID } from 'node:crypto';
import { mkdtemp, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { test } from 'node:test';
import { createReferenceWebhook } from './receiveNote.ts';
import type { ReceiverOptions } from './receiveNote.ts';

const secret = 'non-sensitive-fixture-secret';
const now = 1_800_000_000;
const digest = (bytes: Uint8Array) => createHash('sha256').update(bytes).digest('hex');

function request(noteID: string, overrides: { signature?: string; audio?: Uint8Array; event?: string; timestamp?: number; title?: string } = {}) {
  const audio = overrides.audio ?? new Uint8Array([0, 1, 2, 3]);
  const attemptID = randomUUID();
  const metadata = Buffer.from(JSON.stringify({
    schema_version: 1, event: overrides.event ?? 'note.created', note_id: noteID, attempt_id: attemptID,
    created_at: '2026-09-21T00:00:00Z', duration_ms: 1000, source: 'iphone', title: overrides.title ?? 'Fixture',
    title_source: 'timestamp', capture_outcome: 'completed', workflow_id: 'default',
    audio: { sha256: digest(audio), size_bytes: audio.length }, app: { version: '1.0.0', build: '1' },
  }));
  const timestamp = String(overrides.timestamp ?? now);
  const canonical = ['v1', timestamp, noteID, attemptID, digest(metadata), digest(audio)].join('\n');
  const headers = {
    'X-Whim-Note-ID': noteID, 'X-Whim-Attempt-ID': attemptID, 'X-Whim-Timestamp': timestamp,
    'X-Whim-Metadata-SHA256': digest(metadata), 'X-Whim-Audio-SHA256': digest(audio),
    'X-Whim-Signature': overrides.signature ?? `v1=${createHmac('sha256', secret).update(canonical).digest('hex')}`,
    Authorization: 'Bearer fixture-token',
  };
  const body = new FormData();
  body.append('metadata', new Blob([metadata], { type: 'application/json' }), 'metadata.json');
  body.append('audio', new Blob([audio], { type: 'audio/mp4' }), 'note.m4a');
  return { method: 'POST', headers, body };
}

async function listen(options: ReceiverOptions) {
  const server = createReferenceWebhook(options);
  await new Promise<void>((resolve) => server.listen(0, '127.0.0.1', resolve));
  const address = server.address();
  if (!address || typeof address === 'string') throw new Error('Expected TCP address');
  return {
    url: `http://127.0.0.1:${address.port}/receive`,
    close: () => new Promise<void>((resolve, reject) => server.close(error => error ? reject(error) : resolve())),
  };
}

test('concurrent Attempts share one durable Note across receiver instances and restart', async () => {
  const root = await mkdtemp(join(tmpdir(), 'whim-reference-'));
  const options = { databasePath: join(root, 'notes.sqlite'), hmacSecret: secret, bearerToken: 'fixture-token', now: () => now };
  const first = await listen(options);
  const second = await listen(options);
  const id = randomUUID();
  try {
    const responses = await Promise.all(Array.from({ length: 12 }, (_, i) => fetch(i % 2 ? first.url : second.url, request(id))));
    for (const response of responses) {
      assert.equal(response.status, 200);
      assert.equal(response.headers.get('X-Whim-Note-ID'), id);
    }
    const values = await Promise.all(responses.map(response => response.json()));
    assert.equal(values.filter(value => !value.duplicate).length, 1);
    assert.ok(values.every(value => value.note_id === id));
  } finally { await first.close(); await second.close(); }
  try {
    const restarted = await listen(options);
    try {
      const response = await fetch(restarted.url, request(id));
      assert.equal(response.status, 200);
      assert.deepEqual(await response.json(), { note_id: id, duplicate: true });
    } finally { await restarted.close(); }
  } finally { await rm(root, { recursive: true, force: true }); }
});

test('rejects invalid authentication, tampered parts and expired signatures without storing the Note', async () => {
  const root = await mkdtemp(join(tmpdir(), 'whim-reference-'));
  const receiver = await listen({ databasePath: join(root, 'notes.sqlite'), hmacSecret: secret,
    bearerToken: 'fixture-token', now: () => now });
  try {
    const cases = [
      (value: ReturnType<typeof request>) => { value.headers['X-Whim-Signature'] = 'v1=' + '0'.repeat(64); },
      (value: ReturnType<typeof request>) => { value.headers.Authorization = 'Bearer incorrect'; },
      (value: ReturnType<typeof request>) => { value.headers['X-Whim-Metadata-SHA256'] = '0'.repeat(64); },
      (value: ReturnType<typeof request>) => { value.body.set('audio', new Blob(['tampered'], { type: 'audio/mp4' }), 'note.m4a'); },
      (value: ReturnType<typeof request>) => { value.headers['X-Whim-Note-ID'] = randomUUID(); },
    ];
    for (const alter of cases) {
      const id = randomUUID();
      const value = request(id); alter(value);
      const rejected = await fetch(receiver.url, value);
      assert.ok(rejected.status >= 400 && rejected.status < 500, `Expected rejection, received ${rejected.status}`);
      const valid = await fetch(receiver.url, request(id));
      assert.deepEqual(await valid.json(), { note_id: id, duplicate: false });
    }
    const expired = await fetch(receiver.url, request(randomUUID(), { timestamp: now - 301 }));
    assert.equal(expired.status, 401);
  } finally { await receiver.close(); await rm(root, { recursive: true, force: true }); }
});

test('configuration.test verifies the contract without entering the durable Note inbox', async () => {
  const root = await mkdtemp(join(tmpdir(), 'whim-reference-'));
  const receiver = await listen({ databasePath: join(root, 'notes.sqlite'), hmacSecret: secret, now: () => now });
  try {
    const id = randomUUID();
    const tested = await fetch(receiver.url, request(id, { event: 'configuration.test' }));
    assert.equal(tested.status, 200);
    assert.equal(tested.headers.get('X-Whim-Note-ID'), id);
    const created = await fetch(receiver.url, request(id));
    assert.deepEqual(await created.json(), { note_id: id, duplicate: false });
  } finally { await receiver.close(); await rm(root, { recursive: true, force: true }); }
});


test('hashes exact metadata bytes even when metadata is a text multipart field', async () => {
  const root = await mkdtemp(join(tmpdir(), 'whim-reference-'));
  const receiver = await listen({ databasePath: join(root, 'notes.sqlite'), hmacSecret: secret, now: () => now });
  try {
    const id = randomUUID();
    const value = request(id, { title: '\ufffd' });
    const file = value.body.get('metadata');
    assert.ok(file instanceof Blob);
    value.body.set('metadata', await file.text());
    const encoded = new Request(receiver.url, value);
    const bytes = Buffer.from(await encoded.arrayBuffer());
    const offset = bytes.indexOf(Buffer.from('\ufffd'));
    assert.ok(offset > 0);
    const tampered = Buffer.concat([bytes.subarray(0, offset), Buffer.from([0xff]), bytes.subarray(offset + 3)]);
    const response = await fetch(receiver.url, { method: 'POST', headers: encoded.headers, body: tampered });
    assert.equal(response.status, 400, 'UTF-8 replacement must not hide a modified signed byte sequence');
    const valid = await fetch(receiver.url, { method: 'POST', headers: encoded.headers, body: bytes });
    assert.deepEqual(await valid.json(), { note_id: id, duplicate: false });
  } finally { await receiver.close(); await rm(root, { recursive: true, force: true }); }
});
