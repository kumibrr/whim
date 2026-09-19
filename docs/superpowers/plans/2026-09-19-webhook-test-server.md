# Whim Webhook Test Server Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Extend Whim's local webhook fixture with a browser inbox that lists received Notes and plays their exact submitted audio.

**Architecture:** Keep the existing dependency-free loopback Node process as the sole receiver. Store parsed metadata and audio bytes per Attempt in memory, render an escaped HTML inbox at `/`, and expose retained bytes at `/audio/<attempt-id>` without changing the existing test-control routes.

**Tech Stack:** Node.js built-in `http`, `https`, `crypto`, `fs`, `node:test`, and `fetch`/`FormData` APIs.

**Spec:** `docs/superpowers/specs/2026-09-19-webhook-test-server-design.md`

## Global Constraints

- This is disposable development tooling, not a production backend or persistent data store.
- Bind to `127.0.0.1` and make no external requests.
- Add no runtime dependencies.
- Retain the existing `/state`, `/reset`, `/response`, `/drop`, `/redirect`, `/oversized`, response-status, delay, HMAC, TLS, and port-zero behavior.
- Store and serve exact audio bytes as `audio/mp4`; do not expose request headers or secrets in HTML.
- Keep root `test:unit`, `test:integration`, and `test:e2e` scripts runnable and run `test:all` before completion.

## Review Focus

- Metadata containing HTML or script syntax must render as text, never executable markup; Task 1 tests escaped title output.
- URL-encoded or malformed audio identifiers must not select an unintended record; Task 1 tests a missing identifier returns `404`.
- Two Attempts for one Note must remain separate and only the later Attempt is marked duplicate; Task 1 submits and checks both.
- Reset must invalidate previously issued audio URLs as well as clearing the page; Task 1 checks the old URL after reset.
- Existing automated callers that select port `0` or omit browser routes must observe the same startup and machine-facing behavior; Task 1 starts ephemerally and checks `/state` compatibility.

---

### Task 1: Browser inbox and playable received audio

**Files:**
- Modify: `packages/WhimCore/Sources/WhimCore/WebhookConfiguration/Fixtures/webhook-server.mjs`
- Create: `packages/WhimCore/Sources/WhimCore/WebhookConfiguration/Fixtures/webhook-server.test.mjs`

**Interfaces:**
- Consumes: the existing executable's JSON startup line `{ host, port, tls }`, Whim v1 multipart headers and parts, and `POST /reset`.
- Produces: `GET / -> text/html`, `GET /audio/<attempt-id> -> audio/mp4 | 404`, and received records whose private `audioBytes: Buffer` powers playback while `/state` retains its existing serializable fields.

- [ ] **Step 1: Write the failing HTTP integration test**

Create an adjacent `node:test` file that spawns `webhook-server.mjs` with `WHIM_WEBHOOK_PORT=0`, reads its first JSON line, and terminates the child in `t.after`. Add helpers that compute the two SHA-256 headers and submit this body through `fetch`:

```js
async function submit(baseURL, { noteID, attemptID, title, audio }) {
  const metadata = Buffer.from(JSON.stringify({
    schema_version: 1,
    event: 'note.created',
    note_id: noteID,
    attempt_id: attemptID,
    created_at: '2026-09-19T10:00:00Z',
    duration_ms: 1200,
    source: 'iphone',
    title,
  }));
  const form = new FormData();
  form.append('metadata', new Blob([metadata], { type: 'application/json' }));
  form.append('audio', new Blob([audio], { type: 'audio/mp4' }), 'note.m4a');
  return fetch(`${baseURL}/receive`, {
    method: 'POST',
    headers: {
      'X-Whim-Note-ID': noteID,
      'X-Whim-Attempt-ID': attemptID,
      'X-Whim-Timestamp': '1000',
      'X-Whim-Metadata-SHA256': sha256(metadata),
      'X-Whim-Audio-SHA256': sha256(audio),
    },
    body: form,
  });
}
```

Cover these public behaviors in separate tests:

```js
test('renders an empty browser inbox without changing state JSON', async (t) => {
  const server = await startServer(t);
  const page = await fetch(server.baseURL);
  assert.equal(page.status, 200);
  assert.match(page.headers.get('content-type'), /^text\/html/);
  assert.match(await page.text(), /No audio notes received yet/);
  assert.deepEqual(await (await fetch(`${server.baseURL}/state`)).json(), { received: [] });
});

test('lists escaped attempts newest-first and serves exact audio', async (t) => {
  const server = await startServer(t);
  await submit(server.baseURL, { noteID: NOTE_ID, attemptID: FIRST_ATTEMPT,
    title: '<script>alert(1)</script>', audio: Buffer.from('first-audio') });
  await submit(server.baseURL, { noteID: NOTE_ID, attemptID: SECOND_ATTEMPT,
    title: 'Second attempt', audio: Buffer.from('second-audio') });

  const html = await (await fetch(server.baseURL)).text();
  assert.doesNotMatch(html, /<script>alert\(1\)<\/script>/);
  assert.match(html, /&lt;script&gt;alert\(1\)&lt;\/script&gt;/);
  assert.ok(html.indexOf(SECOND_ATTEMPT) < html.indexOf(FIRST_ATTEMPT));
  assert.match(html, /Duplicate/);

  const audio = await fetch(`${server.baseURL}/audio/${SECOND_ATTEMPT}`);
  assert.equal(audio.status, 200);
  assert.equal(audio.headers.get('content-type'), 'audio/mp4');
  assert.deepEqual(Buffer.from(await audio.arrayBuffer()), Buffer.from('second-audio'));
  assert.equal((await fetch(`${server.baseURL}/audio/missing`)).status, 404);
});

test('reset clears the inbox and invalidates audio URLs', async (t) => {
  const server = await startServer(t);
  await submit(server.baseURL, { noteID: NOTE_ID, attemptID: FIRST_ATTEMPT,
    title: 'Reset me', audio: Buffer.from('audio') });
  assert.equal((await fetch(`${server.baseURL}/audio/${FIRST_ATTEMPT}`)).status, 200);
  assert.equal((await fetch(`${server.baseURL}/reset`, { method: 'POST' })).status, 204);
  assert.equal((await fetch(`${server.baseURL}/audio/${FIRST_ATTEMPT}`)).status, 404);
  assert.match(await (await fetch(server.baseURL)).text(), /No audio notes received yet/);
});
```

- [ ] **Step 2: Run the new test directly and verify red**

Run:

```bash
node --test packages/WhimCore/Sources/WhimCore/WebhookConfiguration/Fixtures/webhook-server.test.mjs
```

Expected: FAIL because `GET /` is handled as an invalid webhook and no audio route exists.

- [ ] **Step 3: Retain parsed audio bytes without changing `/state`**

Change `verify` to return `audioBytes: Buffer.from(audio.bytes)` alongside its current public fields. Before serializing `/state`, omit `audioBytes` so the response shape and base64 multipart `body` remain compatible:

```js
function publicRecord({ audioBytes: _audioBytes, ...record }) {
  return record;
}

// /state
res.end(JSON.stringify({ received: received.map(publicRecord) }));
```

- [ ] **Step 4: Add safe HTML rendering**

Add `escapeHTML`, duration/date formatting, and `renderInbox(records)`. Use escaped text for every metadata value, reverse a copy of `received` for newest-first presentation, include `<audio controls preload="none" src="/audio/${encodeURIComponent(record.attemptID)}"></audio>`, a clear empty state, responsive CSS, and this local refresh behavior:

```html
<script>
  setTimeout(() => location.reload(), 2000);
</script>
```

Handle `GET /` before reading a request body and respond with `content-type: text/html; charset=utf-8`, `cache-control: no-store`, and the rendered page.

- [ ] **Step 5: Add the audio route**

Handle `GET /audio/<attempt-id>` before webhook verification. Decode the final path component defensively, find the record by exact `attemptID`, and return either:

```js
res.writeHead(200, {
  'content-type': 'audio/mp4',
  'content-length': record.audioBytes.length,
  'cache-control': 'no-store',
});
res.end(record.audioBytes);
```

or a plain `404` when decoding fails or no record matches.

- [ ] **Step 6: Run the focused test and existing Swift receiver integration tests**

Run:

```bash
node --test packages/WhimCore/Sources/WhimCore/WebhookConfiguration/Fixtures/webhook-server.test.mjs
npm run test:integration:swift
```

Expected: both commands PASS, proving the browser flow and existing fixture consumers work together.

- [ ] **Step 7: Commit the vertical slice**

```bash
git add packages/WhimCore/Sources/WhimCore/WebhookConfiguration/Fixtures/webhook-server.mjs packages/WhimCore/Sources/WhimCore/WebhookConfiguration/Fixtures/webhook-server.test.mjs
git commit -m "feat: add webhook test server browser inbox"
```

### Task 2: Developer command and root-suite coverage

**Files:**
- Modify: `package.json`

**Interfaces:**
- Consumes: `webhook-server.mjs`, `WHIM_WEBHOOK_PORT`, and Node's test runner.
- Produces: `npm run test-server`, defaulting to loopback port `8787`, and inclusion of the fixture's adjacent test in `npm run test:unit:ts`.

- [ ] **Step 1: Pin the expected package-script behavior with a failing assertion**

Add a test in `webhook-server.test.mjs` that reads the repository `package.json` and asserts exact scripts:

```js
test('root scripts expose the server and run its tests', async () => {
  const packageJSON = JSON.parse(await readFile(new URL('../../../../../../package.json', import.meta.url), 'utf8'));
  assert.equal(packageJSON.scripts['test-server'],
    'WHIM_WEBHOOK_PORT=${WHIM_WEBHOOK_PORT:-8787} node packages/WhimCore/Sources/WhimCore/WebhookConfiguration/Fixtures/webhook-server.mjs');
  assert.match(packageJSON.scripts['test:unit:ts'], /WebhookConfiguration\/Fixtures\/\*\.test\.mjs/);
});
```

- [ ] **Step 2: Run the package-script assertion and verify red**

Run:

```bash
node --test --test-name-pattern='root scripts' packages/WhimCore/Sources/WhimCore/WebhookConfiguration/Fixtures/webhook-server.test.mjs
```

Expected: FAIL because `test-server` is undefined.

- [ ] **Step 3: Add the development and test commands**

Update `package.json` scripts to include:

```json
"test-server": "WHIM_WEBHOOK_PORT=${WHIM_WEBHOOK_PORT:-8787} node packages/WhimCore/Sources/WhimCore/WebhookConfiguration/Fixtures/webhook-server.mjs",
"test:unit:ts": "node --test scripts/*.test.mjs packages/WhimCore/Sources/WhimCore/WebhookConfiguration/Fixtures/*.test.mjs && jest --selectProjects unit"
```

- [ ] **Step 4: Run the root TypeScript/Node unit seam**

Run:

```bash
npm run test:unit:ts
```

Expected: PASS, including the adjacent fixture tests and existing Jest unit project.

- [ ] **Step 5: Commit the developer command**

```bash
git add package.json packages/WhimCore/Sources/WhimCore/WebhookConfiguration/Fixtures/webhook-server.test.mjs
git commit -m "chore: expose webhook test server command"
```

### Task 3: Full verification

**Files:**
- Verify only; no planned file changes.

**Interfaces:**
- Consumes: all repository test scripts after Tasks 1 and 2.
- Produces: evidence that the feature satisfies repository-wide quality gates.

- [ ] **Step 1: Check formatting and repository state**

Run:

```bash
git diff --check HEAD~2
git status --short
```

Expected: no whitespace errors and only intentional changes, if any.

- [ ] **Step 2: Run the full mandated suite**

Run:

```bash
npm run test:all
```

Expected: PASS for root unit, integration, and E2E suites. If Apple hardware behavior cannot run in the current environment, record the exact unavailable acceptance case and ensure the deterministic Node and Swift regression coverage passes.

- [ ] **Step 3: Perform a manual smoke check**

Run `npm run test-server`, open `http://127.0.0.1:8787`, and confirm the empty inbox renders. Submit a Note from Whim or the test helper and confirm its audio controls load and play. Stop the process with `Ctrl-C`.

- [ ] **Step 4: Commit any verification-only correction**

If verification required a code correction, repeat that behavior's red-green cycle and commit only the relevant files. Otherwise, make no empty commit.
