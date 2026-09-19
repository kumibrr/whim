import crypto from "node:crypto";
import fs from "node:fs";
import http from "node:http";
import https from "node:https";

const host = "127.0.0.1";
const port = Number(process.env.WHIM_WEBHOOK_PORT ?? "0");
const hmacSecret = process.env.WHIM_HMAC_SECRET ?? "";
const received = [];
const noteIDs = new Set();
let responseStatus = 200;
let responseDelayMS = 0;

function sha256(bytes) {
  return crypto.createHash("sha256").update(bytes).digest("hex");
}

function header(req, name) {
  const value = req.headers[name.toLowerCase()];
  return Array.isArray(value) ? value[0] : value;
}

function escapeHTML(value) {
  return String(value ?? "").replace(/[&<>"']/g, (character) => ({
    "&": "&amp;",
    "<": "&lt;",
    ">": "&gt;",
    '"': "&quot;",
    "'": "&#39;",
  })[character]);
}

function formatDuration(durationMS) {
  const seconds = Math.max(0, Number(durationMS) || 0) / 1000;
  const minutes = Math.floor(seconds / 60);
  return `${minutes}:${String(Math.floor(seconds % 60)).padStart(2, "0")}`;
}

function formatDate(value) {
  const date = new Date(value);
  return Number.isNaN(date.valueOf()) ? String(value ?? "Unknown time") : date.toLocaleString();
}

function renderInbox(records) {
  const items = records.length === 0
    ? '<div class="empty"><span>🎙️</span><h2>No audio notes received yet</h2><p>Configure Whim to send its webhook to <code>/receive</code>.</p></div>'
    : records.toReversed().map((record) => {
      const metadata = record.json;
      const duplicate = record.duplicate ? '<span class="badge">Duplicate</span>' : "";
      return `<article>
        <div class="card-heading">
          <div><p class="eyebrow">${escapeHTML(metadata.event)}</p><h2>${escapeHTML(metadata.title)}</h2></div>
          ${duplicate}
        </div>
        <audio controls preload="none" src="/audio/${encodeURIComponent(record.attemptID)}"></audio>
        <dl>
          <div><dt>Received</dt><dd>${escapeHTML(formatDate(metadata.created_at))}</dd></div>
          <div><dt>Duration</dt><dd>${escapeHTML(formatDuration(metadata.duration_ms))}</dd></div>
          <div><dt>Source</dt><dd>${escapeHTML(metadata.source)}</dd></div>
          <div><dt>Note ID</dt><dd><code>${escapeHTML(record.noteID)}</code></dd></div>
          <div><dt>Attempt ID</dt><dd><code>${escapeHTML(record.attemptID)}</code></dd></div>
        </dl>
      </article>`;
    }).join("");
  return `<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Whim test server</title>
  <style>
    :root { color-scheme: light dark; font-family: ui-rounded, system-ui, sans-serif; background: #171412; color: #f7eee9; }
    * { box-sizing: border-box; }
    body { margin: 0; min-height: 100vh; background: radial-gradient(circle at top, #35231f, #171412 46%); }
    main { width: min(760px, calc(100% - 32px)); margin: 0 auto; padding: 56px 0; }
    header { margin-bottom: 28px; }
    h1 { margin: 0 0 8px; font-size: clamp(2rem, 8vw, 3.5rem); letter-spacing: -0.05em; }
    header p, .empty p { color: #bca9a0; }
    .list { display: grid; gap: 16px; }
    article, .empty { padding: 24px; border: 1px solid #5c433a; border-radius: 20px; background: #241d1a; box-shadow: 0 18px 50px #0004; }
    .empty { padding: 64px 24px; text-align: center; }
    .empty span { font-size: 2.5rem; }
    .card-heading { display: flex; align-items: start; justify-content: space-between; gap: 16px; }
    h2 { margin: 3px 0 16px; overflow-wrap: anywhere; }
    .eyebrow, dt { margin: 0; color: #f28b74; font-size: .75rem; font-weight: 700; letter-spacing: .08em; text-transform: uppercase; }
    .badge { padding: 5px 9px; border-radius: 999px; background: #f28b74; color: #291511; font-size: .75rem; font-weight: 800; }
    audio { width: 100%; margin: 4px 0 20px; }
    dl { display: grid; grid-template-columns: repeat(3, 1fr); gap: 16px; margin: 0; }
    dl div:nth-last-child(-n + 2) { grid-column: 1 / -1; }
    dd { margin: 4px 0 0; color: #dfd1ca; overflow-wrap: anywhere; }
    code { font-family: ui-monospace, monospace; font-size: .85em; }
    @media (max-width: 560px) { main { padding: 32px 0; } article { padding: 20px; } dl { grid-template-columns: 1fr; } dl div:nth-last-child(-n + 2) { grid-column: auto; } }
  </style>
</head>
<body><main><header><h1>Whim inbox</h1><p>Received audio notes appear here automatically.</p></header><section class="list">${items}</section></main>
<script>
  const refresh = () => {
    const isPlaying = [...document.querySelectorAll("audio")]
      .some((audio) => !audio.paused && !audio.ended);
    if (isPlaying) {
      setTimeout(refresh, 2000);
      return;
    }
    location.reload();
  };
  setTimeout(refresh, 2000);
</script>
</body>
</html>`;
}

function publicRecord({ audioBytes: _audioBytes, ...record }) {
  return record;
}

function parseMultipart(req, body) {
  const contentType = header(req, "content-type") ?? "";
  const match = /boundary=([^;]+)/i.exec(contentType);
  if (!match) throw new Error("missing boundary");
  const boundary = Buffer.from(`--${match[1]}`);
  const parts = [];
  let cursor = body.indexOf(boundary) + boundary.length + 2;
  while (cursor > boundary.length) {
    const headerEnd = body.indexOf(Buffer.from("\r\n\r\n"), cursor);
    if (headerEnd < 0) break;
    const headers = body.subarray(cursor, headerEnd).toString("utf8");
    const next = body.indexOf(Buffer.concat([Buffer.from("\r\n"), boundary]), headerEnd + 4);
    if (next < 0) break;
    parts.push({ headers, bytes: body.subarray(headerEnd + 4, next) });
    cursor = next + 2 + boundary.length + 2;
  }
  const metadata = parts.find((part) => part.headers.includes('name="metadata"'));
  const audio = parts.find((part) => part.headers.includes('name="audio"'));
  if (!metadata || !audio) throw new Error("missing parts");
  return { metadata, audio };
}

function verify(req, body) {
  const { metadata, audio } = parseMultipart(req, body);
  const noteID = header(req, "x-whim-note-id");
  const attemptID = header(req, "x-whim-attempt-id");
  const timestamp = header(req, "x-whim-timestamp");
  if (typeof noteID !== "string" || noteID.length === 0
      || typeof attemptID !== "string" || attemptID.length === 0) {
    throw new Error("missing identity");
  }
  const metadataDigest = sha256(metadata.bytes);
  const audioDigest = sha256(audio.bytes);
  if (metadataDigest !== header(req, "x-whim-metadata-sha256")) throw new Error("metadata digest");
  if (audioDigest !== header(req, "x-whim-audio-sha256")) throw new Error("audio digest");
  const json = JSON.parse(metadata.bytes.toString("utf8"));
  if (json.note_id !== noteID || json.attempt_id !== attemptID) throw new Error("identity");
  if (typeof json.event !== "string" || typeof json.title !== "string"
      || typeof json.created_at !== "string" || typeof json.source !== "string"
      || typeof json.duration_ms !== "number" || !Number.isFinite(json.duration_ms)) {
    throw new Error("metadata");
  }
  if (hmacSecret) {
    const input = `v1\n${timestamp}\n${noteID}\n${attemptID}\n${metadataDigest}\n${audioDigest}`;
    const expected = `v1=${crypto.createHmac("sha256", hmacSecret).update(input).digest("hex")}`;
    const actual = header(req, "x-whim-signature") ?? "";
    if (actual.length !== expected.length || !crypto.timingSafeEqual(Buffer.from(actual), Buffer.from(expected))) {
      throw new Error("signature");
    }
  }
  return {
    noteID,
    attemptID,
    json,
    duplicate: noteIDs.has(noteID),
    body: body.toString("base64"),
    audioBytes: Buffer.from(audio.bytes),
  };
}

const handleRequest = (req, res) => {
  const url = new URL(req.url ?? "/", `http://${host}`);
  if (req.method === "GET" && url.pathname === "/") {
    res.writeHead(200, { "content-type": "text/html; charset=utf-8", "cache-control": "no-store" });
    res.end(renderInbox(received));
    return;
  }
  if (req.method === "GET" && url.pathname.startsWith("/audio/")) {
    let attemptID;
    try { attemptID = decodeURIComponent(url.pathname.slice("/audio/".length)); }
    catch {
      res.writeHead(404, { "content-type": "text/plain; charset=utf-8" }).end("audio not found");
      return;
    }
    const record = received.find((item) => item.attemptID === attemptID);
    if (!record) {
      res.writeHead(404, { "content-type": "text/plain; charset=utf-8" }).end("audio not found");
      return;
    }
    res.writeHead(200, {
      "content-type": "audio/mp4",
      "content-length": record.audioBytes.length,
      "cache-control": "no-store",
    });
    res.end(record.audioBytes);
    return;
  }
  if (req.method === "POST" && url.pathname === "/reset") {
    received.length = 0;
    noteIDs.clear();
    responseStatus = 200;
    responseDelayMS = 0;
    res.writeHead(204).end();
    return;
  }
  if (req.method === "GET" && url.pathname === "/state") {
    res.setHeader("content-type", "application/json");
    res.end(JSON.stringify({ received: received.map(publicRecord) }));
    return;
  }
  const chunks = [];
  req.on("data", (chunk) => chunks.push(chunk));
  req.on("end", () => {
    if (req.method === "POST" && url.pathname === "/response") {
      try {
        const { status, delay_ms = 0 } = JSON.parse(Buffer.concat(chunks).toString("utf8"));
        if (!Number.isInteger(status) || status < 200 || status > 599) throw new Error("invalid status");
        if (!Number.isInteger(delay_ms) || delay_ms < 0 || delay_ms > 30000) throw new Error("invalid delay");
        responseStatus = status;
        responseDelayMS = delay_ms;
        res.writeHead(204).end();
      } catch {
        res.writeHead(400).end("invalid response status");
      }
      return;
    }
    if (url.pathname === "/drop") { req.socket.destroy(); return; }
    let record;
    try {
      record = verify(req, Buffer.concat(chunks));
      received.push(record);
      noteIDs.add(record.noteID);
    } catch {
      res.writeHead(400).end("invalid webhook contract");
      return;
    }
    const respond = () => {
      if (url.pathname === "/redirect") {
        res.writeHead(302, { location: "/receive" }).end();
      } else if (url.pathname === "/oversized") {
        res.writeHead(500, { "content-type": "text/plain" }).end("x".repeat(8192));
      } else {
        const status = Number(url.searchParams.get("status") ?? responseStatus);
        const headers = { "content-type": "application/json", "x-whim-note-id": record.noteID };
        if (url.searchParams.has("retry_after")) headers["retry-after"] = url.searchParams.get("retry_after");
        if (url.pathname === "/invalid-ack") delete headers["x-whim-note-id"];
        const body = url.pathname === "/invalid-ack" ? "{}" : JSON.stringify({ note_id: record.noteID, duplicate: record.duplicate });
        res.writeHead(status, headers).end(body);
      }
    };
    const delay = Number(url.searchParams.get("delay_ms") ?? responseDelayMS);
    if (delay > 0) setTimeout(respond, delay); else respond();
  });
};

const tlsKeyPath = process.env.WHIM_TLS_KEY_PATH;
const tlsCertificatePath = process.env.WHIM_TLS_CERT_PATH;
const usesTLS = Boolean(tlsKeyPath && tlsCertificatePath);
const server = usesTLS
  ? https.createServer({
      key: fs.readFileSync(tlsKeyPath),
      cert: fs.readFileSync(tlsCertificatePath),
    }, handleRequest)
  : http.createServer(handleRequest);

server.listen(port, host, () => {
  const address = server.address();
  process.stdout.write(`${JSON.stringify({ host, port: address.port, tls: usesTLS })}\n`);
});

for (const signal of ["SIGTERM", "SIGINT"]) {
  process.on(signal, () => server.close(() => process.exit(0)));
}
