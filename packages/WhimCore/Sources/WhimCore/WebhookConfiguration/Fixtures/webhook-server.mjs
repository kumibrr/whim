import crypto from "node:crypto";
import http from "node:http";

const host = "127.0.0.1";
const port = Number(process.env.WHIM_WEBHOOK_PORT ?? "0");
const hmacSecret = process.env.WHIM_HMAC_SECRET ?? "";
const received = [];
const noteIDs = new Set();

function sha256(bytes) {
  return crypto.createHash("sha256").update(bytes).digest("hex");
}

function header(req, name) {
  const value = req.headers[name.toLowerCase()];
  return Array.isArray(value) ? value[0] : value;
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
  const metadataDigest = sha256(metadata.bytes);
  const audioDigest = sha256(audio.bytes);
  if (metadataDigest !== header(req, "x-whim-metadata-sha256")) throw new Error("metadata digest");
  if (audioDigest !== header(req, "x-whim-audio-sha256")) throw new Error("audio digest");
  const json = JSON.parse(metadata.bytes.toString("utf8"));
  if (json.note_id !== noteID || json.attempt_id !== attemptID) throw new Error("identity");
  if (hmacSecret) {
    const input = `v1\n${timestamp}\n${noteID}\n${attemptID}\n${metadataDigest}\n${audioDigest}`;
    const expected = `v1=${crypto.createHmac("sha256", hmacSecret).update(input).digest("hex")}`;
    const actual = header(req, "x-whim-signature") ?? "";
    if (actual.length !== expected.length || !crypto.timingSafeEqual(Buffer.from(actual), Buffer.from(expected))) {
      throw new Error("signature");
    }
  }
  return { noteID, attemptID, json, duplicate: noteIDs.has(noteID), body: body.toString("base64") };
}

const server = http.createServer((req, res) => {
  const url = new URL(req.url ?? "/", `http://${host}`);
  if (req.method === "POST" && url.pathname === "/reset") {
    received.length = 0;
    noteIDs.clear();
    res.writeHead(204).end();
    return;
  }
  if (req.method === "GET" && url.pathname === "/state") {
    res.setHeader("content-type", "application/json");
    res.end(JSON.stringify({ received }));
    return;
  }
  const chunks = [];
  req.on("data", (chunk) => chunks.push(chunk));
  req.on("end", () => {
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
        const status = Number(url.searchParams.get("status") ?? "200");
        const headers = { "content-type": "application/json", "x-whim-note-id": record.noteID };
        if (url.searchParams.has("retry_after")) headers["retry-after"] = url.searchParams.get("retry_after");
        if (url.pathname === "/invalid-ack") delete headers["x-whim-note-id"];
        const body = url.pathname === "/invalid-ack" ? "{}" : JSON.stringify({ note_id: record.noteID, duplicate: record.duplicate });
        res.writeHead(status, headers).end(body);
      }
    };
    const delay = Number(url.searchParams.get("delay_ms") ?? "0");
    if (delay > 0) setTimeout(respond, delay); else respond();
  });
});

server.listen(port, host, () => {
  const address = server.address();
  process.stdout.write(`${JSON.stringify({ host, port: address.port })}\n`);
});

for (const signal of ["SIGTERM", "SIGINT"]) {
  process.on(signal, () => server.close(() => process.exit(0)));
}
