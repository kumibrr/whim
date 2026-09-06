import type { CaptureSource } from '../recording/RecordingProjection';

export type DeliveryStatus = 'setup_required' | 'queued' | 'sending' | 'sent' | 'failed';
export type LocalAudioError = 'storageFull' | 'unreadable' | 'missing' | 'durabilityFailure';

export type NoteProjection = {
  schemaVersion: 1;
  id: string;
  title: string;
  createdAt: string;
  durationSeconds: number;
  source: CaptureSource;
  status: DeliveryStatus;
  requiresReview: boolean;
  hasLocalAudio: boolean;
  localError: LocalAudioError | null;
};

export type AttemptProjection = {
  id: string;
  configurationRevisionID: string;
  device: CaptureSource;
  startedAt: string;
  destination: { scheme: string; host: string; port: number | null; path: string };
  outcome: 'sending' | 'failed' | 'sent';
  failureReason: string | null;
  responseStatusCode: number | null;
};

export type NoteDetailProjection = NoteProjection & { attempts: AttemptProjection[] };
