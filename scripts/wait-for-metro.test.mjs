import assert from 'node:assert/strict';
import test from 'node:test';

import { waitForMetro } from './wait-for-metro.mjs';

test('probes localhost so IPv4-only and IPv6-only Metro listeners both work', async () => {
  const requestedURLs = [];
  const ready = await waitForMetro({
    attempts: 1,
    fetchFn: async (url) => {
      requestedURLs.push(url);
      return { ok: true, text: async () => 'packager-status:running' };
    },
  });

  assert.equal(ready, true);
  assert.deepEqual(requestedURLs, ['http://localhost:8081/status']);
});

test('does not accept a stale Metro response after the spawned process exits', async () => {
  let fetched = false;
  const ready = await waitForMetro({
    attempts: 1,
    fetchFn: async () => {
      fetched = true;
      return { ok: true, text: async () => 'packager-status:running' };
    },
    processAliveFn: () => false,
    processID: 42,
  });

  assert.equal(ready, false);
  assert.equal(fetched, false);
});

test('probes a caller-selected Metro port while its process is alive', async () => {
  const requestedURLs = [];
  const ready = await waitForMetro({
    attempts: 1,
    fetchFn: async (url) => {
      requestedURLs.push(url);
      return { ok: true, text: async () => 'packager-status:running' };
    },
    processAliveFn: () => true,
    processID: 42,
    url: 'http://localhost:49152/status',
  });

  assert.equal(ready, true);
  assert.deepEqual(requestedURLs, ['http://localhost:49152/status']);
});
