import fixture from './notes-v1.fixture.json';
import swiftPackageFixture from '../../../WhimCore/Sources/WhimCore/AppComposition/Fixtures/notes-v1.fixture.json';
import { isWhimEvent, type WhimEvent } from './WhimEvent';

describe('notes-v1 native event contract', () => {
  it('decodes the shared fixture with stable enum values, optionals, dates, and schema version', () => {
    expect(swiftPackageFixture).toEqual(fixture);
    expect(fixture.every(isWhimEvent)).toBe(true);
    const events = fixture as WhimEvent[];

    expect(events.map((event) => event.type)).toEqual([
      'recording.started',
      'recording.progress',
      'recording.route_changed',
      'recording.maximum_duration_warning',
      'recording.stopped',
      'recording.discarded',
      'note.changed',
      'note.changed',
      'note.changed',
      'note.changed',
      'note.changed',
      'note.deleted',
      'notes.reset',
    ]);
    expect(events.map((event) => event.sequence)).toEqual([1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13]);
    expect(events.every((event) => event.schemaVersion === 1)).toBe(true);
    const started = events[0];
    expect(started.type).toBe('recording.started');
    if (started.type !== 'recording.started') throw new Error('fixture did not start recording');
    expect(new Date(started.recording.createdAt).toISOString()).toBe('2026-09-04T20:20:00.000Z');
    expect(events[1]).toMatchObject({ elapsedSeconds: 42.25, peakPowerDBFS: -18.5 });
    const changed = events[6];
    expect(changed.type).toBe('note.changed');
    if (changed.type !== 'note.changed') throw new Error('fixture did not change a Note');
    expect(changed.note).toMatchObject({
      source: 'apple_watch',
      status: 'failed',
      localError: 'unreadable',
      workflowError: 'delivery_preparation_failed',
    });
    expect(events.slice(6, 11).map((event) => event.type === 'note.changed' && event.note.status)).toEqual([
      'failed', 'setup_required', 'queued', 'sending', 'sent',
    ]);
    expect(events.slice(6, 11).map((event) => event.type === 'note.changed' && event.note.localError)).toEqual([
      'unreadable', 'storageFull', 'missing', 'durabilityFailure', null,
    ]);
    expect(events.slice(6, 11).map((event) => event.type === 'note.changed' && event.note.workflowError)).toEqual([
      'delivery_preparation_failed', 'delivery_persistence_failed', null, null, null,
    ]);
    expect('note' in events[12]).toBe(false);
  });
});
