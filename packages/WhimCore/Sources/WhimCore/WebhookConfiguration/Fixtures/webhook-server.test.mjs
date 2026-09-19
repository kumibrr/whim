import assert from "node:assert/strict";
import crypto from "node:crypto";
import { once } from "node:events";
import { spawn } from "node:child_process";
import { createInterface } from "node:readline";
import test from "node:test";
import { fileURLToPath } from "node:url";
import vm from "node:vm";

const NOTE_ID = "11111111-1111-4111-8111-111111111111";
const FIRST_ATTEMPT = "22222222-2222-4222-8222-222222222222";
const SECOND_ATTEMPT = "33333333-3333-4333-8333-333333333333";

function sha256(bytes) {
  return crypto.createHash("sha256").update(bytes).digest("hex");
}

async function startServer(t) {
  const script = fileURLToPath(new URL("./webhook-server.mjs", import.meta.url));
  const child = spawn(process.execPath, [script], {
    env: { ...process.env, WHIM_WEBHOOK_PORT: "0" },
    stdio: ["ignore", "pipe", "pipe"],
  });
  let errors = "";
  child.stderr.setEncoding("utf8");
  child.stderr.on("data", (chunk) => { errors += chunk; });
  const [chunk] = await Promise.race([
    once(child.stdout, "data"),
    once(child, "exit").then(([code]) => { throw new Error(`Server exited ${code}: ${errors}`); }),
  ]);
  const startup = JSON.parse(chunk.toString("utf8").split("\n")[0]);
  t.after(async () => {
    if (child.exitCode === null) {
      child.kill("SIGTERM");
      await once(child, "exit");
    }
    assert.equal(errors, "");
  });
  return { baseURL: `http://${startup.host}:${startup.port}` };
}

async function submit(baseURL, { noteID, attemptID, title, audio }) {
  const metadataJSON = {
    schema_version: 1,
    event: "note.created",
    note_id: noteID,
    created_at: "2026-09-19T10:00:00Z",
    duration_ms: 1200,
    source: "iphone",
    title,
    title_source: "transcription",
    capture_outcome: "completed",
    workflow_id: "default",
    audio: { sha256: sha256(audio), size_bytes: audio.length },
    app: { version: "1.0.0", build: "1" },
  };
  if (attemptID !== undefined) metadataJSON.attempt_id = attemptID;
  const metadata = Buffer.from(JSON.stringify(metadataJSON));
  const form = new FormData();
  form.append("metadata", new Blob([metadata], { type: "application/json" }));
  form.append("audio", new Blob([audio], { type: "audio/mp4" }), "note.m4a");
  const headers = {
    "X-Whim-Note-ID": noteID,
    "X-Whim-Timestamp": "1000",
    "X-Whim-Metadata-SHA256": sha256(metadata),
    "X-Whim-Audio-SHA256": sha256(audio),
  };
  if (attemptID !== undefined) headers["X-Whim-Attempt-ID"] = attemptID;
  return fetch(`${baseURL}/receive`, {
    method: "POST",
    headers,
    body: form,
  });
}

async function startServerThroughNPM(t) {
  const repositoryRoot = fileURLToPath(new URL("../../../../../../", import.meta.url));
  const child = spawn("npm", ["run", "--silent", "test-server"], {
    cwd: repositoryRoot,
    detached: true,
    env: { ...process.env, WHIM_WEBHOOK_PORT: "0" },
    stdio: ["ignore", "pipe", "pipe"],
  });
  let errors = "";
  child.stderr.setEncoding("utf8");
  child.stderr.on("data", (chunk) => { errors += chunk; });
  const lines = createInterface({ input: child.stdout });
  const startup = await Promise.race([
    (async () => {
      for await (const line of lines) {
        if (line.startsWith("{")) return JSON.parse(line);
      }
      throw new Error(`Server produced no startup line: ${errors}`);
    })(),
    once(child, "exit").then(([code]) => { throw new Error(`npm exited ${code}: ${errors}`); }),
  ]);
  t.after(async () => {
    if (child.exitCode === null) {
      process.kill(-child.pid, "SIGTERM");
      await once(child, "exit");
    }
    assert.equal(errors, "");
  });
  return { baseURL: `http://${startup.host}:${startup.port}` };
}

test("renders an empty browser inbox without changing state JSON", async (t) => {
  const server = await startServer(t);
  const page = await fetch(server.baseURL);
  assert.equal(page.status, 200);
  assert.match(page.headers.get("content-type"), /^text\/html/);
  const html = await page.text();
  assert.match(html, /No audio notes received yet/);
  assert.match(html, /<p>IP address: (?:\d{1,3}\.){3}\d{1,3}<\/p>/);
  assert.deepEqual(await (await fetch(`${server.baseURL}/state`)).json(), { received: [] });
});

test("lists escaped attempts newest-first and serves exact audio", async (t) => {
  const server = await startServer(t);
  assert.equal((await submit(server.baseURL, { noteID: NOTE_ID, attemptID: FIRST_ATTEMPT,
    title: "<script>alert(1)</script>", audio: Buffer.from("first-audio") })).status, 200);
  assert.equal((await submit(server.baseURL, { noteID: NOTE_ID, attemptID: SECOND_ATTEMPT,
    title: "Second attempt", audio: Buffer.from("second-audio") })).status, 200);

  const html = await (await fetch(server.baseURL)).text();
  assert.doesNotMatch(html, /<script>alert\(1\)<\/script>/);
  assert.match(html, /&lt;script&gt;alert\(1\)&lt;\/script&gt;/);
  assert.ok(html.indexOf(SECOND_ATTEMPT) < html.indexOf(FIRST_ATTEMPT));
  const cards = html.match(/<article>[\s\S]*?<\/article>/g);
  assert.equal(cards.length, 2);
  assert.match(cards[0], /Duplicate/);
  assert.doesNotMatch(cards[1], /Duplicate/);

  const audio = await fetch(`${server.baseURL}/audio/${SECOND_ATTEMPT}`);
  assert.equal(audio.status, 200);
  assert.equal(audio.headers.get("content-type"), "audio/mp4");
  assert.deepEqual(Buffer.from(await audio.arrayBuffer()), Buffer.from("second-audio"));
  assert.equal((await fetch(`${server.baseURL}/audio/missing`)).status, 404);
  assert.equal((await fetch(`${server.baseURL}/audio/%E0%A4%A`)).status, 404);
});

test("refresh waits for active playback and resumes when audio is idle", async (t) => {
  const server = await startServer(t);
  const html = await (await fetch(server.baseURL)).text();
  const script = html.match(/<script>([\s\S]*?)<\/script>/)[1];
  const audio = { paused: false, ended: false };
  const timers = [];
  let reloads = 0;
  vm.runInNewContext(script, {
    document: { querySelectorAll: () => [audio] },
    location: { reload: () => { reloads += 1; } },
    setTimeout: (callback) => { timers.push(callback); },
  });

  assert.equal(timers.length, 1);
  timers.shift()();
  assert.equal(reloads, 0);
  assert.equal(timers.length, 1);
  audio.paused = true;
  timers.shift()();
  assert.equal(reloads, 1);
});

test("rejects missing identities instead of retaining addressable audio", async (t) => {
  const server = await startServer(t);
  const response = await submit(server.baseURL, { noteID: NOTE_ID, attemptID: undefined,
    title: "Missing attempt", audio: Buffer.from("private-audio") });
  assert.equal(response.status, 400);
  assert.deepEqual(await (await fetch(`${server.baseURL}/state`)).json(), { received: [] });
  assert.equal((await fetch(`${server.baseURL}/audio/%E0%A4%A`)).status, 404);
});

test("rejects non-renderable metadata without terminating the server", async (t) => {
  const server = await startServer(t);
  const response = await submit(server.baseURL, { noteID: NOTE_ID, attemptID: FIRST_ATTEMPT,
    title: { toString: null }, audio: Buffer.from("audio") });
  assert.equal(response.status, 400);
  const page = await fetch(server.baseURL);
  assert.equal(page.status, 200);
  assert.match(await page.text(), /No audio notes received yet/);
});

test("reset clears the inbox and invalidates audio URLs", async (t) => {
  const server = await startServer(t);
  assert.equal((await submit(server.baseURL, { noteID: NOTE_ID, attemptID: FIRST_ATTEMPT,
    title: "Reset me", audio: Buffer.from("audio") })).status, 200);
  assert.equal((await fetch(`${server.baseURL}/audio/${FIRST_ATTEMPT}`)).status, 200);
  assert.equal((await fetch(`${server.baseURL}/reset`, { method: "POST" })).status, 204);
  assert.equal((await fetch(`${server.baseURL}/audio/${FIRST_ATTEMPT}`)).status, 404);
  assert.match(await (await fetch(server.baseURL)).text(), /No audio notes received yet/);
});

test("root test-server command starts the browser inbox", async (t) => {
  const server = await startServerThroughNPM(t);
  const response = await fetch(server.baseURL);
  assert.equal(response.status, 200);
  assert.match(await response.text(), /Whim inbox/);
});
