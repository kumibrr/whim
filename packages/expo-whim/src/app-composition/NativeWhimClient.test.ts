import type { WhimClient } from './NativeWhimClient';
import { NativeWhimClient, WhimClientError, type RawExpoWhimModule } from './NativeWhimClient';

describe('NativeWhimClient', () => {
  it('implements the exact async client contract and decodes native projections and events', async () => {
    const raw = new RawModuleFake();
    const client: WhimClient = new NativeWhimClient(raw);
    const events: string[] = [];
    const subscription = client.subscribe((event) => events.push(event.type));

    const recording = await client.startRecording('iphone');
    raw.emit({ schemaVersion: 1, sequence: 1, type: 'recording.started', recording });
    const notes = await client.listNotes('all');
    subscription.remove();

    expect(recording.noteID).toBe('22222222-2222-2222-2222-222222222222');
    expect(notes[0].status).toBe('queued');
    expect(events).toEqual(['recording.started']);
  });

  it('maps native failures to stable redacted code, message, and field values', async () => {
    const client = new NativeWhimClient(new RawModuleFake(JSON.stringify({
      code: 'invalid_configuration',
      message: 'Enter a valid HTTPS endpoint.',
      field: 'endpoint',
    })));

    await expect(client.updateWebhook({
      endpoint: 'https://user:super-secret@example.com',
      bearerToken: 'super-secret',
      hmacSecret: null,
      customHeaders: [],
    })).rejects.toEqual(new WhimClientError(
      'invalid_configuration',
      'Enter a valid HTTPS endpoint.',
      'endpoint',
    ));
  });

  it('extracts a stable payload when Expo prefixes the native error description', async () => {
    const raw = new RawModuleFake('Call to updateWebhook was rejected: {"code":"invalid_configuration","message":"Invalid.","field":"endpoint"}');
    await expect(new NativeWhimClient(raw).updateWebhook({ endpoint: 'bad', customHeaders: [] }))
      .rejects.toEqual(new WhimClientError('invalid_configuration', 'Invalid.', 'endpoint'));
  });
});

class RawModuleFake implements RawExpoWhimModule {
  private listener?: (event: unknown) => void;
  constructor(private readonly updateError?: string) {}
  schemaVersion = () => 1;
  startRecording = async () => JSON.stringify({ schemaVersion: 1, sessionID: '11111111-1111-1111-1111-111111111111', noteID: '22222222-2222-2222-2222-222222222222', source: 'iphone', createdAt: '2026-09-04T20:20:00.000Z' });
  getActiveRecording = async () => 'null';
  stopRecording = async () => 'null';
  discardRecording = async () => undefined;
  listNotes = async () => JSON.stringify([{ schemaVersion: 1, id: '22222222-2222-2222-2222-222222222222', title: 'Idea', createdAt: '2026-09-04T20:20:00.000Z', durationSeconds: 1, source: 'iphone', status: 'queued', requiresReview: false, hasLocalAudio: true, localError: null }]);
  getNote = async () => 'null';
  retry = async () => undefined;
  retryAllFailed = async () => 0;
  sendRecovered = async () => undefined;
  deleteNote = async () => undefined;
  updateWebhook = async () => { if (this.updateError) throw new Error(this.updateError); return '{}'; };
  testWebhook = async () => '{}';
  updatePreferences = async () => undefined;
  reset = async () => undefined;
  addListener(_name: 'onWhimEvent', listener: (event: unknown) => void) {
    this.listener = listener;
    return { remove: () => { this.listener = undefined; } };
  }
  emit(event: unknown) { this.listener?.(event); }
}

const compileTimeExactFake = {
  startRecording: async () => ({ schemaVersion: 1, sessionID: '', noteID: '', source: 'iphone', createdAt: '' }),
  getActiveRecording: async () => null,
  stopRecording: async () => null,
  discardRecording: async () => {},
  listNotes: async () => [],
  getNote: async () => null,
  retry: async () => {},
  retryAllFailed: async () => 0,
  sendRecovered: async () => {},
  deleteNote: async () => {},
  updateWebhook: async () => ({ revisionID: '', failedCount: 0, setupRequiredCount: 0 }),
  testWebhook: async () => ({ passed: true, statusCode: 204, idempotencyConfirmed: true }),
  updatePreferences: async () => {},
  reset: async () => {},
  subscribe: () => ({ remove() {} }),
} satisfies WhimClient;

void compileTimeExactFake;
