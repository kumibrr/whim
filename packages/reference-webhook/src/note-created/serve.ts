import { resolve } from 'node:path';
import { createReferenceWebhook } from './receiveNote.ts';

const host = process.env.WHIM_WEBHOOK_HOST ?? '127.0.0.1';
const port = Number(process.env.WHIM_WEBHOOK_PORT ?? 8788);
const server = createReferenceWebhook({
  databasePath: resolve(process.env.WHIM_WEBHOOK_DATABASE ?? 'whim-inbox.sqlite'),
  hmacSecret: process.env.WHIM_HMAC_SECRET,
  bearerToken: process.env.WHIM_BEARER_TOKEN,
});
server.listen(port, host, () => console.log(`Whim reference receiver listening on ${host}:${port}`));
for (const signal of ['SIGINT', 'SIGTERM'] as const) {
  process.once(signal, () => server.close(error => { process.exitCode = error ? 1 : 0; }));
}
