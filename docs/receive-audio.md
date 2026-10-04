# Receive Whim audio on your own server

Whim sends each finalized Note directly to a webhook you control. This guide runs the included reference receiver, connects Whim to it, and shows how to retrieve the audio. You do not need Xcode or the Apple app source build tools on the server.

The receiver accepts AAC `.m4a` audio and JSON metadata, verifies authentication and file hashes, and saves them together in a SQLite inbox. Repeated deliveries of the same Note create only one row, including when iPhone and Apple Watch both send it. The receiver provides storage; add your own processing if you want transcription, notifications, or another downstream Workflow destination.

Use [local setup](#try-it-on-your-local-network) to try a delivery over Wi-Fi, or [Linux server setup](#run-on-a-linux-server) for an endpoint reachable away from home. The [webhook contract](webhook-contract-v1.md) describes requests and responses if you want to build another receiver.

## Try it on your local network

You need Git, [Node.js 24 or newer](https://nodejs.org/en/download) with npm, and OpenSSL on a Mac or Linux computer. Node includes the receiver's runtime dependencies; no `npm ci`, TypeScript compilation, or separate database server is needed.

```sh
git clone https://github.com/kumibrr/whim.git
cd whim
node --version
```

Generate two different secrets. Save the first as your bearer token and the second as your HMAC secret in your password manager:

```sh
openssl rand -hex 32
openssl rand -hex 32
```

Replace the placeholders below with those values. Keep the database outside the checkout so replacing the source does not remove your Notes:

```sh
mkdir -p "$HOME/.local/share/whim"
chmod 700 "$HOME/.local/share/whim"
export WHIM_WEBHOOK_DATABASE="$HOME/.local/share/whim/inbox.sqlite"
export WHIM_BEARER_TOKEN='<your bearer token>'
export WHIM_HMAC_SECRET='<your HMAC secret>'
WHIM_WEBHOOK_HOST=0.0.0.0 npm start --workspace @whim/reference-webhook
```

Leave this terminal open. The receiver listens on port `8788`; allow that port through the computer's firewall for your local network. Avoid forwarding it to the internet. The secrets above may be retained in your shell history; the Linux setup below uses a protected environment file instead.

Find the computer's private IPv4 address in its network settings, for example `192.168.1.50`. Connect your iPhone to the same network, then use `http://192.168.1.50:8788/receive` as the Webhook URL in [Connect Whim](#connect-whim). Replace the example IP with your computer's address. Whim accepts HTTP on private IPv4 networks; public endpoints require HTTPS. HTTP exposes audio and credentials to the network, so use this setup only on a trusted network.

`127.0.0.1` on a physical iPhone points to the iPhone itself. Use the computer's private address, and check that Wi-Fi client isolation or a VPN is not blocking access. This endpoint works only while your devices can reach that local network and the computer is awake. Press Ctrl-C to stop the receiver; restart with the same database path to keep the inbox.

## Run on a Linux server

This example uses a Debian or Ubuntu server with systemd, a dedicated receiver account, and Caddy for HTTPS. You need sudo access, a domain such as `audio.example.com`, and enough persistent disk space for your recordings.

### 1. Install the tools and source

Install [Node.js 24 or newer](https://nodejs.org/en/download) system-wide, and install Caddy using its [official Debian/Ubuntu instructions](https://caddyserver.com/docs/install#debian-ubuntu-raspbian). The Caddy package installs its systemd service. Then install the other tools:

```sh
sudo apt update
sudo apt install -y git curl openssl sqlite3
node --version
command -v node
caddy version
sudo git clone https://github.com/kumibrr/whim.git /opt/whim
sudo useradd --system --user-group --home-dir /var/lib/whim --shell /usr/sbin/nologin whim
sudo install -d -o whim -g whim -m 0700 /var/lib/whim
```

The service below assumes Node is at `/usr/bin/node`. If `command -v node` shows another system-wide path, use that path in `ExecStart`. A Node installation inside your login account's home directory may be inaccessible to the service.

### 2. Configure the receiver

Generate two different secrets with `openssl rand -hex 32`, as in local setup, and save them in your password manager. Create a protected file:

```sh
sudo install -m 0600 /dev/null /etc/whim-webhook.env
sudoedit /etc/whim-webhook.env
```

Put the following in `/etc/whim-webhook.env`, replacing both secret placeholders. Keep one assignment per line, without `export`:

```ini
WHIM_WEBHOOK_HOST=127.0.0.1
WHIM_WEBHOOK_PORT=8788
WHIM_WEBHOOK_DATABASE=/var/lib/whim/inbox.sqlite
WHIM_BEARER_TOKEN=<your bearer token>
WHIM_HMAC_SECRET=<your HMAC secret>
```

| Setting | Purpose | Default if omitted |
| --- | --- | --- |
| `WHIM_WEBHOOK_HOST` | Interface to listen on | `127.0.0.1` |
| `WHIM_WEBHOOK_PORT` | HTTP port | `8788` |
| `WHIM_WEBHOOK_DATABASE` | SQLite file; its parent directory must exist and be writable | `whim-inbox.sqlite` in the working directory |
| `WHIM_BEARER_TOKEN` | Require a matching bearer token | No token check |
| `WHIM_HMAC_SECRET` | Require signed requests and enforce five-minute clock tolerance | No signature check |

Keep both secrets set for this public endpoint. Whim must use exactly the same values. Generated hex secrets are used as literal text: do not decode them before entering them in the app.

### 3. Start a persistent service

Create `/etc/systemd/system/whim-webhook.service` with `sudoedit`:

```ini
[Unit]
Description=Whim audio receiver
After=network.target

[Service]
Type=simple
User=whim
Group=whim
WorkingDirectory=/opt/whim
EnvironmentFile=/etc/whim-webhook.env
ExecStart=/usr/bin/node /opt/whim/packages/reference-webhook/src/note-created/serve.ts
Restart=on-failure
RestartSec=5
UMask=0077

[Install]
WantedBy=multi-user.target
```

Start it now and enable it after reboot:

```sh
sudo systemctl daemon-reload
sudo systemctl enable --now whim-webhook
sudo systemctl status whim-webhook --no-pager
curl -i http://127.0.0.1:8788/receive
```

The curl request should return `405` because `/receive` accepts POST, not GET. This checks that the process is reachable; Whim's configuration test will verify an authenticated delivery. The SQLite file is created on startup.

### 4. Add HTTPS

Point your domain's DNS `A` record at the server's public IPv4 address. If you publish an `AAAA` record, it must point to working IPv6 on the same server. Allow inbound TCP ports `80` and `443` through your host and hosting-provider firewalls. Keep port `8788` private.

Caddy obtains and renews the certificate when the domain points to this server and those ports are reachable. See its [HTTPS quick-start](https://caddyserver.com/docs/quick-starts/https) for the DNS and network prerequisites.

Add this site to `/etc/caddy/Caddyfile`, replacing `audio.example.com` with your domain. Preserve any sites you already host:

```caddyfile
audio.example.com {
    reverse_proxy 127.0.0.1:8788
}
```

Validate the file and reload the service:

```sh
sudo caddy validate --config /etc/caddy/Caddyfile --adapter caddyfile
sudo systemctl enable --now caddy
sudo systemctl reload caddy
curl -i https://audio.example.com/receive
```

Expect `405` again, this time over a valid HTTPS connection. Use `https://audio.example.com/receive` in Whim. Enter the HTTPS URL directly: Whim rejects redirects, including an HTTP-to-HTTPS redirect. Use a publicly trusted certificate; Whim does not bypass certificate validation.

## Connect Whim

1. On your iPhone, open Whim and tap the settings button, then **Webhook**.
2. Enter your **Webhook URL**, including `/receive`.
3. Enter the server's **Bearer token** without the `Bearer ` prefix, and its **HMAC secret**. No custom headers are needed for this receiver.
4. Tap **Save**, then **Test webhook**. Testing is disabled while you have unsaved edits.
5. After the test passes, record a short Note, tap Stop, and open history to check that it becomes **Sent**. Use **Retry unsent Notes** if Whim offers it for Notes awaiting setup or a retry.

The configuration test sends the bundled test audio with `event: "configuration.test"`. The receiver validates and acknowledges it but does **not** save it in the inbox. Record a real Note to check storage. A real Note is acknowledged with HTTP `200` and its Note ID; a repeat is also successful and returns `duplicate: true`.

Webhook configuration synchronizes from iPhone to your paired Apple Watch. Wait for synchronization before testing Watch delivery. A public HTTPS endpoint lets the Watch send when it has its own usable network connection.

## Find and export your audio

The receiver stores recordings inside SQLite, rather than as individual files. It has no browser inbox or audio download route. On the Linux server, list the received Note IDs and audio sizes:

```sh
sudo -u whim sqlite3 -header -column /var/lib/whim/inbox.sqlite \
  'SELECT note_id, length(audio) AS audio_bytes FROM notes;'
```

To export one Note, replace `<note UUID>` with an ID from that query. This writes `<note UUID>.m4a` and `<note UUID>.json` into `/var/lib/whim/exports`:

```sh
sudo -u whim /usr/bin/node --input-type=module - \
  /var/lib/whim/inbox.sqlite '<note UUID>' /var/lib/whim/exports <<'JS'
import { DatabaseSync } from 'node:sqlite';
import { mkdirSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';

const [databasePath, noteID, outputDirectory] = process.argv.slice(2);
const database = new DatabaseSync(databasePath, { readOnly: true });
try {
  const note = database.prepare('SELECT note_id, metadata, audio FROM notes WHERE note_id = ?')
    .get(noteID.toLowerCase());
  if (!note) throw new Error('Note not found');
  mkdirSync(outputDirectory, { recursive: true, mode: 0o700 });
  writeFileSync(join(outputDirectory, `${note.note_id}.m4a`), note.audio, { mode: 0o600 });
  writeFileSync(join(outputDirectory, `${note.note_id}.json`), note.metadata, { mode: 0o600 });
} finally {
  database.close();
}
JS
```

Use your Node executable's actual path if different. For local setup, run the same Node snippet without `sudo -u whim`, using your local database and export-directory paths.

Your own worker can consume `notes` rows as durable work items. Use `note_id` as the downstream service's idempotency key and keep track of processed IDs; the receiver does not mark rows as processed. It keeps the first accepted payload, so a later title generated on iPhone does not replace a title already received from Watch.

## Keep the inbox recoverable

Keep `/var/lib/whim` on persistent storage and monitor disk space. The inbox, exported files, and backups contain your complete recordings and metadata. The receiver has no automatic retention cleanup. Whim's Retention Policy, Delete, and Reset affect device storage; they do not delete server copies. See [Whim privacy](privacy.md).

Use SQLite's backup command to take a consistent snapshot while the receiver runs. On this Linux setup:

```sh
sudo install -d -m 0700 /var/backups/whim
sudo sqlite3 /var/lib/whim/inbox.sqlite \
  ".backup '/var/backups/whim/inbox.sqlite'"
sudo chmod 0600 /var/backups/whim/inbox.sqlite
```

This replaces the previous snapshot at that path. Keep protected copies off the server too. To restore, stop `whim-webhook`, restore the database to `/var/lib/whim/inbox.sqlite` with owner `whim:whim` and mode `0600`, then start the service. Restoring the inbox also restores the saved Note IDs used for deduplication. Removing an inbox row allows that Note ID to be accepted as new work again.

Inspect service startup and errors with:

```sh
sudo journalctl -u whim-webhook -n 50 --no-pager
sudo journalctl -u caddy -n 50 --no-pager
```

The receiver logs its listening address but does not log request bodies, credentials, Note titles, or audio. After changing its environment file, restart it with `sudo systemctl restart whim-webhook`. Update Whim's saved secrets and test again if you rotate them; a disconnected Watch may retain older credentials until it reconnects.

## Troubleshooting

Check **Settings → Webhook errors** in Whim for failed Attempts.

| Symptom | What to check |
| --- | --- |
| Cannot connect | Receiver/service status, domain/IP, firewall, and device network access. For local setup, use the computer's address, keep it awake, and bind `0.0.0.0`. |
| Certificate or redirect error | Use the final HTTPS URL with a trusted certificate. Check DNS and Caddy logs. |
| `401` | The token and HMAC secret must match the server. Check automatic time settings on the device and server; signed requests allow five minutes of clock difference. |
| `404` | The path must be `/receive`, with no trailing slash, and the reverse proxy must preserve that path. |
| `405` | GET is expected to fail; use **Test webhook** for a real POST. |
| `400` from a custom sender | Check the multipart body, metadata schema, and hashes against the [contract](webhook-contract-v1.md). |
| `413` | The complete multipart request exceeds the receiver's 32 MiB limit, or a proxy has a smaller limit. |
| `500` or `502` | Check database permissions/disk space, receiver startup, Node version, and proxy logs. |
| Test passes but inbox is empty | Configuration tests are intentionally not stored. Record and stop a real Note. |
| A Sent Note does not resend | Whim preserves successful Delivery. Record a new Note to test a new destination. |

Network failures and retryable responses are retried automatically, up to three actual failures. Most `4xx` responses fail immediately. After repairing the server or configuration, use Whim's Retry action for failed Notes. See the [contract's retry rules](webhook-contract-v1.md#idempotency-and-responses).

`npm run test-server` starts a separate development fixture with a temporary browser inbox. Use `npm start --workspace @whim/reference-webhook` for the persistent receiver described here.
