# Whim webhook contract v1

Whim sends one `multipart/form-data` POST per Attempt to the configured endpoint. Parts are `metadata` (`application/json`, exact UTF-8 bytes) and `audio` (`audio/mp4`, an AAC `.m4a` file). The configured endpoint receives the audio, title, capture timestamp/duration, source device kind, workflow ID, app version/build, and Note/Attempt IDs. Whim does not have a hosted relay.

The JSON has `schema_version: 1`, `event: "note.created"`, `note_id`, `attempt_id`, `created_at` (UTC ISO-8601), `duration_ms`, `source` (`iphone` or `apple_watch`), `title`, `title_source` (`transcription`, `timestamp`, or `recovered`), `capture_outcome` (`completed`, `interrupted`, or `recovered`), `workflow_id`, `audio: { sha256, size_bytes }`, and `app: { version, build }`. The complete example is in the [v1 design](superpowers/specs/2026-09-04-whim-v1-design.md#webhook-request-contract).

Each request carries these headers:

| Header | Value |
| --- | --- |
| `X-Whim-Note-ID` | Immutable Note UUID; the idempotency key |
| `X-Whim-Attempt-ID` | UUID identifying this transport Attempt |
| `X-Whim-Timestamp` | Unix seconds at request creation |
| `X-Whim-Metadata-SHA256` | Lowercase hex SHA-256 of the exact metadata bytes |
| `X-Whim-Audio-SHA256` | Lowercase hex SHA-256 of the exact audio bytes |
| `Authorization` | `Bearer <token>` when configured |
| `X-Whim-Signature` | `v1=<lowercase hex HMAC-SHA256>` when configured |

Compute HMAC with the configured secret over this UTF-8 text, with newline separators and **no trailing newline**:

```text
v1
<timestamp>
<note_id>
<attempt_id>
<metadata_sha256>
<audio_sha256>
```

Verify the raw part hashes before using their content. Do not reserialize JSON to compute the metadata digest. Compare signatures in constant time. The reference receiver allows five minutes of clock skew for signed requests; keep server/device clocks accurate.

## Idempotency and responses

The iPhone and Watch may concurrently deliver the same Note with different Attempt IDs, titles, or Configuration Revisions. A lost response can also produce a later retry. Atomically store or enqueue one logical work item keyed by **Note ID**. A duplicate valid request should return success and the original Note ID without creating downstream work again. Keep the first accepted payload; Attempt IDs are not deduplication keys.

Any `2xx` response creates a Receipt in Whim. Echo the ID in `X-Whim-Note-ID` and preferably JSON:

```json
{ "note_id": "the-note-uuid", "duplicate": false }
```

The same acknowledgement with `duplicate: true` is returned for a duplicate. Network failures, `408`, `425`, `429`, and `5xx` are retryable; other `4xx` fail immediately. Redirects are rejected. Automatic retries stop after three actual failures, with earliest retry delays of one minute and fifteen minutes; `429 Retry-After` can defer eligibility. OS background scheduling may delay an eligible Attempt further.

`event: "configuration.test"` uses the same body/signature contract with a fresh Note and Attempt ID. Validate it and echo its Note ID, but do not enqueue it as a user Note. Missing ID acknowledgement produces a setup warning in Whim even when the HTTP response succeeds.

## Reference receiver

Requires Node 24+. The receiver is a separate, self-hosted example; it is not shipped in the apps or operated by Whim.

```sh
npm ci
WHIM_WEBHOOK_DATABASE=/absolute/path/inbox.sqlite \
WHIM_HMAC_SECRET='your-secret' \
WHIM_BEARER_TOKEN='your-token' \
npm start --workspace @whim/reference-webhook
```

Default binding is `127.0.0.1:8788`; use `/receive`. Set `WHIM_WEBHOOK_HOST` and `WHIM_WEBHOOK_PORT` as needed. Terminate HTTPS at your controlled reverse proxy for a deployed endpoint. Protect the database and its backups: it contains complete audio and metadata. No request bodies, credentials, titles, or audio are logged by the receiver.

The SQLite `notes` inbox has a unique `note_id` and stores the first metadata/audio payload atomically. Consume those rows as durable work items. The example does not promise exactly-once side effects in a separate downstream service; pass the Note ID as that service's idempotency key too. Requests are capped at 32 MiB, and malformed or unauthenticated bodies never enter the inbox. Requests without a configured secret/token are allowed for local testing.

Run `npm run test:integration:webhook` for concurrent HTTP requests against separate SQLite connections, restart persistence, authentication/tamper rejection, and configuration-test behavior.
