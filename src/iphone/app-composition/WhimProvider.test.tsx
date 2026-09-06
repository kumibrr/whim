import { act, render, screen, waitFor } from '@testing-library/react-native';
import { AppState, Text, type AppStateStatus } from 'react-native';

jest.mock('expo-modules-core', () => ({
  requireNativeModule: () => ({ schemaVersion: () => 1, addListener: () => ({ remove() {} }) }),
}));

import { WhimClientError, type WhimEvent, type WhimClient, type NoteProjection, type RecordingProjection } from '@whim/expo-whim';
import { WhimProvider, useWhim } from './WhimProvider';

const note: NoteProjection = {
  schemaVersion: 1,
  id: '22222222-2222-2222-2222-222222222222',
  title: 'Fresh Note',
  createdAt: '2026-09-04T20:20:00.000Z',
  durationSeconds: 42,
  source: 'iphone',
  status: 'queued',
  requiresReview: false,
  hasLocalAudio: true,
  localError: null,
};
const recording: RecordingProjection = {
  schemaVersion: 1,
  sessionID: '11111111-1111-1111-1111-111111111111',
  noteID: note.id,
  source: 'iphone',
  createdAt: note.createdAt,
};

describe('WhimProvider', () => {
  it('subscribes before initial list and preserves an event that arrives during the list request', async () => {
    const client = new ClientFake();
    await render(<WhimProvider client={client}><Probe /></WhimProvider>);
    expect(client.calls.slice(0, 2)).toEqual(['subscribe', 'list']);

    await act(() => client.emit({ schemaVersion: 1, sequence: 1, type: 'note.changed', note }));
    await act(async () => client.resolveList([]));

    expect(await screen.findByText('Fresh Note')).toBeOnTheScreen();
  });

  it('fully refreshes after an event sequence gap and an app foreground transition', async () => {
    const client = new ClientFake();
    let appStateListener: ((state: AppStateStatus) => void) | undefined;
    jest.spyOn(AppState, 'addEventListener').mockImplementation((_event, listener) => {
      appStateListener = listener;
      return { remove: jest.fn() };
    });
    await render(<WhimProvider client={client}><Probe /></WhimProvider>);
    await act(async () => client.resolveList([]));

    await act(() => client.emit({ schemaVersion: 1, sequence: 2, type: 'note.changed', note }));
    await waitFor(() => expect(client.listCount).toBe(2));
    await act(async () => client.resolveList([note]));
    await act(() => appStateListener?.('background'));
    await act(() => appStateListener?.('active'));
    await waitFor(() => expect(client.listCount).toBe(3));
  });

  it('surfaces refresh failures without an unhandled effect rejection', async () => {
    const client = new ClientFake();
    await render(<WhimProvider client={client}><Probe /></WhimProvider>);
    await act(async () => client.rejectList(new WhimClientError('store_unavailable', 'Notes unavailable.')));
    expect(await screen.findByText('store_unavailable')).toBeOnTheScreen();
  });

  it('resynchronizes active recording when a stopped event was missed', async () => {
    const client = new ClientFake();
    client.activeRecording = recording;
    await render(<WhimProvider client={client}><Probe /></WhimProvider>);
    await act(async () => client.resolveList([]));
    expect(await screen.findByText(`recording:${recording.noteID}`)).toBeOnTheScreen();

    client.activeRecording = null;
    await act(() => client.emit({ schemaVersion: 1, sequence: 3, type: 'note.changed', note }));
    await waitFor(() => expect(client.listCount).toBe(2));
    await act(async () => client.resolveList([note]));

    expect(await screen.findByText('Fresh Note')).toBeOnTheScreen();
  });

  it('ignores an older overlapping refresh that resolves after the newest snapshot', async () => {
    const client = new ClientFake();
    const older = { ...note, id: '33333333-3333-3333-3333-333333333333', title: 'Older Snapshot' };
    const newer = { ...note, id: '44444444-4444-4444-4444-444444444444', title: 'Newest Snapshot' };
    await render(<WhimProvider client={client}><Probe /></WhimProvider>);
    await act(async () => client.resolveList([]));

    await act(async () => {
      client.requestRefresh?.();
      client.requestRefresh?.();
    });
    await waitFor(() => expect(client.listCount).toBe(3));
    await act(async () => client.resolveListAt(1, [newer]));
    await act(async () => client.resolveListAt(0, [older]));

    expect(await screen.findByText('Newest Snapshot')).toBeOnTheScreen();
  });

  it('resets sequence and rejects a stale snapshot when the client is replaced', async () => {
    const first = new ClientFake();
    const second = new ClientFake();
    const old = { ...note, title: 'Old Client' };
    const fresh = { ...note, id: '77777777-7777-7777-7777-777777777777', title: 'New Client' };
    const rendered = await render(<WhimProvider client={first}><Probe /></WhimProvider>);
    await waitFor(() => expect(first.listCount).toBe(1));
    await act(() => first.emit({ schemaVersion: 1, sequence: 10, type: 'note.changed', note: old }));

    await rendered.rerender(<WhimProvider client={second}><Probe /></WhimProvider>);
    await waitFor(() => expect(second.listCount).toBe(1));
    await act(() => second.emit({ schemaVersion: 1, sequence: 1, type: 'note.changed', note: fresh }));
    await act(async () => second.resolveList([]));
    await act(async () => first.resolveList([old]));

    expect(await screen.findByText('New Client')).toBeOnTheScreen();
    expect(first.subscriptionRemoved).toBe(true);
  });
});

function Probe() {
  const { notes, recording: active, error, refresh } = useWhim();
  ClientFake.latestRefresh = refresh;
  return <Text>{error?.code ?? (active ? `recording:${active.noteID}` : notes[0]?.title) ?? 'empty'}</Text>;
}

class ClientFake implements WhimClient {
  static latestRefresh?: () => Promise<void>;
  calls: string[] = [];
  listCount = 0;
  activeRecording: RecordingProjection | null = null;
  subscriptionRemoved = false;
  private listener?: (event: WhimEvent) => void;
  private resolvers: Array<{ resolve(notes: NoteProjection[]): void; reject(error: Error): void }> = [];
  subscribe(listener: (event: WhimEvent) => void) {
    this.calls.push('subscribe'); this.listener = listener;
    return { remove: () => { this.listener = undefined; this.subscriptionRemoved = true; } };
  }
  listNotes = async () => { this.calls.push('list'); this.listCount += 1; return new Promise<NoteProjection[]>((resolve, reject) => this.resolvers.push({ resolve, reject })); };
  resolveList(notes: NoteProjection[]) { this.resolvers.shift()?.resolve(notes); }
  resolveListAt(index: number, notes: NoteProjection[]) { this.resolvers.splice(index, 1)[0]?.resolve(notes); }
  rejectList(error: Error) { this.resolvers.shift()?.reject(error); }
  emit(event: WhimEvent) { this.listener?.(event); }
  startRecording: WhimClient['startRecording'] = async () => { throw new Error('unused'); };
  getActiveRecording = async () => this.activeRecording;
  requestRefresh = () => { void ClientFake.latestRefresh?.(); };
  stopRecording = async () => null;
  discardRecording = async () => {};
  getNote = async () => null;
  retry = async () => {};
  retryAllFailed = async () => 0;
  sendRecovered = async () => {};
  deleteNote = async () => {};
  updateWebhook: WhimClient['updateWebhook'] = async () => { throw new Error('unused'); };
  testWebhook: WhimClient['testWebhook'] = async () => { throw new Error('unused'); };
  updatePreferences = async () => {};
  reset = async () => {};
}
