import type { EventSubscription } from 'expo-modules-core';

import type { WhimEvent } from '../events/WhimEvent';
import { isWhimEvent } from '../events/WhimEvent';
import type { NoteDetailProjection, NoteProjection } from '../notes/NoteProjection';
import type { PreferenceInput } from '../preferences/PreferenceInput';
import type { CaptureSource, RecordingProjection } from '../recording/RecordingProjection';
import type {
  ConfigurationTestResult,
  ConfigurationUpdateResult,
  WebhookConfigurationInput,
} from '../webhook-configuration/WebhookProjection';

export type NoteFilter = 'all' | 'queued' | 'failed' | 'sent';

export interface WhimClient {
  startRecording(source: CaptureSource): Promise<RecordingProjection>;
  getActiveRecording(): Promise<RecordingProjection | null>;
  stopRecording(): Promise<NoteProjection | null>;
  discardRecording(): Promise<void>;
  listNotes(filter: NoteFilter): Promise<NoteProjection[]>;
  getNote(id: string): Promise<NoteDetailProjection | null>;
  retry(noteID: string): Promise<void>;
  retryAllFailed(): Promise<number>;
  sendRecovered(noteID: string): Promise<void>;
  deleteNote(noteID: string): Promise<void>;
  updateWebhook(input: WebhookConfigurationInput): Promise<ConfigurationUpdateResult>;
  testWebhook(): Promise<ConfigurationTestResult>;
  updatePreferences(input: PreferenceInput): Promise<void>;
  reset(): Promise<void>;
  subscribe(listener: (event: WhimEvent) => void): EventSubscription;
}

export interface RawExpoWhimModule {
  schemaVersion(): number;
  startRecording(source: CaptureSource): Promise<string>;
  getActiveRecording(): Promise<string>;
  stopRecording(): Promise<string>;
  discardRecording(): Promise<void>;
  listNotes(filter: NoteFilter): Promise<string>;
  getNote(id: string): Promise<string>;
  retry(noteID: string): Promise<void>;
  retryAllFailed(): Promise<number>;
  sendRecovered(noteID: string): Promise<void>;
  deleteNote(noteID: string): Promise<void>;
  updateWebhook(input: string): Promise<string>;
  testWebhook(): Promise<string>;
  updatePreferences(input: string): Promise<void>;
  reset(): Promise<void>;
  addListener(name: 'onWhimEvent', listener: (event: unknown) => void): EventSubscription;
}

export class WhimClientError extends Error {
  constructor(
    readonly code: string,
    message: string,
    readonly field?: string,
  ) {
    super(message);
    this.name = 'WhimClientError';
  }
}

export class NativeWhimClient implements WhimClient {
  constructor(private readonly native: RawExpoWhimModule) {}

  startRecording(source: CaptureSource) {
    return this.invoke(() => this.native.startRecording(source), decodeJSON<RecordingProjection>);
  }
  getActiveRecording() {
    return this.invoke(() => this.native.getActiveRecording(), decodeJSON<RecordingProjection | null>);
  }
  stopRecording() {
    return this.invoke(() => this.native.stopRecording(), decodeJSON<NoteProjection | null>);
  }
  discardRecording() { return this.invoke(() => this.native.discardRecording()); }
  listNotes(filter: NoteFilter) {
    return this.invoke(() => this.native.listNotes(filter), decodeJSON<NoteProjection[]>);
  }
  getNote(id: string) {
    return this.invoke(() => this.native.getNote(id), decodeJSON<NoteDetailProjection | null>);
  }
  retry(noteID: string) { return this.invoke(() => this.native.retry(noteID)); }
  retryAllFailed() { return this.invoke(() => this.native.retryAllFailed()); }
  sendRecovered(noteID: string) { return this.invoke(() => this.native.sendRecovered(noteID)); }
  deleteNote(noteID: string) { return this.invoke(() => this.native.deleteNote(noteID)); }
  updateWebhook(input: WebhookConfigurationInput) {
    return this.invoke(() => this.native.updateWebhook(JSON.stringify(input)), decodeJSON<ConfigurationUpdateResult>);
  }
  testWebhook() {
    return this.invoke(() => this.native.testWebhook(), decodeJSON<ConfigurationTestResult>);
  }
  updatePreferences(input: PreferenceInput) {
    return this.invoke(() => this.native.updatePreferences(JSON.stringify(input)));
  }
  reset() { return this.invoke(() => this.native.reset()); }

  subscribe(listener: (event: WhimEvent) => void): EventSubscription {
    return this.native.addListener('onWhimEvent', (value) => {
      if (isWhimEvent(value)) listener(value);
    });
  }

  private async invoke<T, R = T>(operation: () => Promise<T>, decode?: (value: T) => R): Promise<R> {
    try {
      const value = await operation();
      return decode ? decode(value) : value as unknown as R;
    } catch (error) {
      throw normalizeError(error);
    }
  }
}

function decodeJSON<T>(value: string): T {
  return JSON.parse(value) as T;
}

function normalizeError(error: unknown): WhimClientError {
  const raw = error instanceof Error ? error.message : String(error);
  const payload = raw.match(/\{[^{}]*\}\s*$/)?.[0] ?? raw;
  try {
    const parsed = JSON.parse(payload) as { code?: unknown; message?: unknown; field?: unknown };
    if (typeof parsed.code === 'string' && typeof parsed.message === 'string') {
      return new WhimClientError(parsed.code, parsed.message,
        typeof parsed.field === 'string' ? parsed.field : undefined);
    }
  } catch { /* native error was not a structured Whim error */ }
  return new WhimClientError('native_failure', 'Whim could not complete the request.');
}
