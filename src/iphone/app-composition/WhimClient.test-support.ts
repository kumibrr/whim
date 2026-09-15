import type { NoteDetailProjection, NoteProjection, RecordingProjection, WhimEvent, WhimClient, SettingsProjection, PlaybackProjection, PermissionKind, PreferenceInput, WebhookPatch } from '@whim/expo-whim';

export function settingsFixture(): SettingsProjection {
  return { schemaVersion: 1, preferences: { retentionPolicy: 'thirty_days', transcriptionEnabled: true, transcriptionLocaleIdentifier: null },
    onboardingCompleted: false, permissions: { microphone: 'not_determined', speech: 'not_determined', notifications: 'not_determined' },
    webhook: null, watch: { availability: 'unavailable', lastSynchronizedAt: null, resetState: 'unavailable' } };
}
export function noteFixture(overrides: Partial<NoteDetailProjection> = {}): NoteDetailProjection {
  return { schemaVersion: 1, id: '22222222-2222-2222-2222-222222222222', title: 'A thought', createdAt: '2026-09-05T12:00:00.000Z', durationSeconds: 42,
    source: 'iphone', status: 'queued', requiresReview: false, hasLocalAudio: true, localError: null, workflowError: null, attempts: [], ...overrides };
}
/** Contract fake for the native system boundary; real provider, routes and screens run together. */
export class TestWhimClient implements WhimClient {
  settings = settingsFixture();
  notes: NoteDetailProjection[] = [];
  recording: RecordingProjection | null = null;
  playback: PlaybackProjection | null = null;
  calls: string[] = [];
  patches: WebhookPatch[] = [];
  private listeners = new Set<(event: WhimEvent) => void>();
  private sequence = 0;
  emit(event: WhimEvent) { this.listeners.forEach(listener => listener(event)); }
  change(note: NoteDetailProjection) { this.notes = [note, ...this.notes.filter(n => n.id !== note.id)]; this.emit({ schemaVersion: 1, sequence: ++this.sequence, type: 'note.changed', note }); }
  getSettings = async () => this.settings;
  completeOnboarding = async () => { this.calls.push('completeOnboarding'); this.settings = { ...this.settings, onboardingCompleted: true }; };
  requestPermission = async (kind: PermissionKind) => { this.calls.push(`permission:${kind}`); this.settings = { ...this.settings, permissions: { ...this.settings.permissions, [kind]: 'granted' } }; return this.settings.permissions[kind]; };
  openSystemSettings = async () => { this.calls.push('openSystemSettings'); };
  updatePreferences = async (preferences: PreferenceInput) => { this.settings = { ...this.settings, preferences }; };
  patchWebhook = async (input: WebhookPatch) => { this.patches.push(input); return { revisionID: 'revision', failedCount: 1, setupRequiredCount: 0 }; };
  updateWebhook: WhimClient['updateWebhook'] = async () => ({ revisionID: 'revision', failedCount: 0, setupRequiredCount: 0 });
  testWebhook = async () => ({ passed: true, statusCode: 204, idempotencyConfirmed: false });
  playNote = async (id: string) => { this.calls.push(`play:${id}`); this.playback = { schemaVersion: 1, noteID: id, isPlaying: true, elapsedSeconds: 0, durationSeconds: 42 }; return this.playback; };
  stopPlayback = async () => { this.playback = null; };
  getPlayback = async () => this.playback;
  startRecording: WhimClient['startRecording'] = async source => {
    this.calls.push(`start:${source}`);
    this.recording ??= { schemaVersion: 1, sessionID: 'session', noteID: noteFixture().id, source, createdAt: new Date().toISOString(), maximumDurationSeconds: 300, warningLeadSeconds: 15 };
    this.emit({ schemaVersion: 1, sequence: ++this.sequence, type: 'recording.started', recording: this.recording }); return this.recording;
  };
  getActiveRecording = async () => this.recording;
  finalizeRecording(note = noteFixture()) { this.recording = null; this.notes = [note, ...this.notes.filter(n => n.id !== note.id)]; this.emit({ schemaVersion: 1, sequence: ++this.sequence, type: 'recording.stopped' }); this.change(note); return note; }
  stopRecording = async () => { this.calls.push('stop'); return this.finalizeRecording(); };
  discardRecording = async () => { this.calls.push('discard'); this.recording = null; this.emit({ schemaVersion: 1, sequence: ++this.sequence, type: 'recording.discarded' }); };
  listNotes = async (): Promise<NoteProjection[]> => this.notes;
  getNote = async (id: string) => this.notes.find(note => note.id === id) ?? null;
  retry = async (id: string) => { this.calls.push(`retry:${id}`); };
  retryAllFailed = async () => { this.calls.push('retryAllFailed'); return 1; };
  sendRecovered = async (id: string) => { this.calls.push(`send:${id}`); this.change(noteFixture({ id, requiresReview: false })); };
  deleteNote = async (id: string) => { this.calls.push(`delete:${id}`); this.notes = this.notes.filter(n => n.id !== id); this.emit({ schemaVersion: 1, sequence: ++this.sequence, type: 'note.deleted', noteID: id }); };
  reset = async () => { this.calls.push('reset'); this.notes = []; this.settings = settingsFixture(); this.recording = null; this.playback = null; this.emit({ schemaVersion: 1, sequence: ++this.sequence, type: 'notes.reset' }); };
  subscribe(listener: (event: WhimEvent) => void) { this.listeners.add(listener); return { remove: () => { this.listeners.delete(listener); } }; }
}
