import type { NoteProjection } from '../notes/NoteProjection';
import type { RecordingProjection } from '../recording/RecordingProjection';

type EventBase = { schemaVersion: 1; sequence: number };

export type WhimEvent =
  | (EventBase & { type: 'recording.started'; recording: RecordingProjection })
  | (EventBase & {
      type: 'recording.progress';
      elapsedSeconds?: number;
      peakPowerDBFS?: number;
    })
  | (EventBase & { type: 'recording.stopped' | 'recording.discarded' })
  | (EventBase & { type: 'recording.route_changed' | 'recording.maximum_duration_warning' })
  | (EventBase & { type: 'note.changed'; note: NoteProjection })
  | (EventBase & { type: 'note.deleted'; noteID: string })
  | (EventBase & { type: 'notes.reset' });

const eventTypes = new Set<WhimEvent['type']>([
  'recording.started',
  'recording.progress',
  'recording.stopped',
  'recording.discarded',
  'recording.route_changed',
  'recording.maximum_duration_warning',
  'note.changed',
  'note.deleted',
  'notes.reset',
]);

export function isWhimEvent(value: unknown): value is WhimEvent {
  if (typeof value !== 'object' || value === null) return false;
  const event = value as Record<string, unknown>;
  if (
    event.schemaVersion !== 1 ||
    !Number.isSafeInteger(event.sequence) ||
    (event.sequence as number) < 1 ||
    typeof event.type !== 'string' ||
    !eventTypes.has(event.type as WhimEvent['type'])
  ) return false;
  switch (event.type) {
    case 'recording.started':
      return isVersionedObject(event.recording) && isISODate(event.recording.createdAt);
    case 'recording.progress':
      return optionalNumber(event.elapsedSeconds) && optionalNumber(event.peakPowerDBFS);
    case 'note.changed':
      return isVersionedObject(event.note) && isISODate(event.note.createdAt);
    case 'note.deleted':
      return typeof event.noteID === 'string';
    default:
      return true;
  }
}

function isVersionedObject(value: unknown): value is Record<string, unknown> & { schemaVersion: 1 } {
  return typeof value === 'object' && value !== null && (value as { schemaVersion?: unknown }).schemaVersion === 1;
}

function isISODate(value: unknown): value is string {
  return typeof value === 'string' && !Number.isNaN(Date.parse(value)) && new Date(value).toISOString() === value;
}

function optionalNumber(value: unknown): boolean {
  return value === undefined || typeof value === 'number';
}
