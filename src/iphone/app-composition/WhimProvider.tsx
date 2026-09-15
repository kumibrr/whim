import { WhimClientError, whimClient, type NoteProjection, type RecordingProjection, type WhimClient, type WhimEvent, type SettingsProjection, type PlaybackProjection } from '@whim/expo-whim';
import { createContext, type PropsWithChildren, useCallback, useContext, useEffect, useMemo, useRef, useState } from 'react';
import { AppState } from 'react-native';

export type WhimContextValue = {
  client: WhimClient;
  notes: NoteProjection[];
  recording: RecordingProjection | null;
  settings: SettingsProjection | null;
  playback: PlaybackProjection | null;
  isRefreshing: boolean;
  error: WhimClientError | null;
  refresh(): Promise<void>;
};

const WhimContext = createContext<WhimContextValue | null>(null);

export function WhimProvider({ children, client = whimClient }: PropsWithChildren<{ client?: WhimClient }>) {
  const [notes, setNotes] = useState<NoteProjection[]>([]);
  const [recording, setRecording] = useState<RecordingProjection | null>(null);
  const [settings, setSettings] = useState<SettingsProjection | null>(null);
  const [playback, setPlayback] = useState<PlaybackProjection | null>(null);
  const [isRefreshing, setRefreshing] = useState(false);
  const [error, setError] = useState<WhimClientError | null>(null);
  const lastSequence = useRef(0);
  const eventLog = useRef<WhimEvent[]>([]);
  const refreshPending = useRef(false);
  const refreshGeneration = useRef(0);
  const mounted = useRef(true);

  const refresh = useCallback(async () => {
    const generation = ++refreshGeneration.current;
    const startingSequence = lastSequence.current;
    refreshPending.current = true;
    setRefreshing(true);
    setError(null);
    try {
      const [snapshot, activeRecording, currentSettings, currentPlayback] = await Promise.all([
        client.listNotes('all'), client.getActiveRecording(), client.getSettings(), client.getPlayback(),
      ]);
      if (!mounted.current || generation !== refreshGeneration.current) return;
      const events = eventLog.current.filter((event) => event.sequence > startingSequence);
      setNotes(events.reduce(foldNotes, snapshot));
      setRecording(events.reduce(foldRecording, activeRecording));
      setSettings(currentSettings); setPlayback(currentPlayback);
    } catch (failure) {
      const clientError = failure instanceof WhimClientError
        ? failure
        : new WhimClientError('refresh_failed', 'Notes could not be refreshed.');
      if (mounted.current && generation === refreshGeneration.current) setError(clientError);
      throw clientError;
    } finally {
      if (generation === refreshGeneration.current) {
        refreshPending.current = false;
        eventLog.current = [];
        if (mounted.current) setRefreshing(false);
      }
    }
  }, [client]);

  useEffect(() => {
    mounted.current = true;
    lastSequence.current = 0;
    eventLog.current = [];
    refreshPending.current = false;
    refreshGeneration.current += 1;
    setNotes([]); setRecording(null); setSettings(null); setPlayback(null); setError(null);
    const subscription = client.subscribe((event) => {
      if (event.sequence <= lastSequence.current) return;
      const gap = event.sequence !== lastSequence.current + 1;
      lastSequence.current = event.sequence;
      if (refreshPending.current) eventLog.current.push(event);
      setNotes((current) => foldNotes(current, event));
      if (event.type === 'recording.started') setRecording(event.recording);
      if (event.type === 'recording.stopped' || event.type === 'recording.discarded' || event.type === 'notes.reset') {
        setRecording(null);
      }
      if (gap || event.type === 'settings.changed') void refresh().catch(() => {});
      if (event.type === 'notes.reset') { setPlayback(null); void refresh().catch(() => {}); }
    });
    void refresh().catch(() => {});
    let previousState = AppState.currentState;
    const appStateSubscription = AppState.addEventListener('change', (state) => {
      if (state === 'active' && previousState !== 'active') void refresh().catch(() => {});
      previousState = state;
    });
    return () => {
      mounted.current = false;
      refreshGeneration.current += 1;
      refreshPending.current = false;
      eventLog.current = [];
      subscription.remove();
      appStateSubscription.remove();
    };
  }, [client, refresh]);

  const value = useMemo(() => ({ client, notes, recording, settings, playback, isRefreshing, error, refresh }),
    [client, notes, recording, settings, playback, isRefreshing, error, refresh]);
  return <WhimContext.Provider value={value}>{children}</WhimContext.Provider>;
}

export function useWhim(): WhimContextValue {
  const value = useContext(WhimContext);
  if (!value) throw new Error('useWhim must be used inside WhimProvider.');
  return value;
}

function foldNotes(notes: NoteProjection[], event: WhimEvent): NoteProjection[] {
  if (event.type === 'notes.reset') return [];
  if (event.type === 'note.deleted') return notes.filter((note) => note.id !== event.noteID);
  if (event.type !== 'note.changed') return notes;
  const withoutChanged = notes.filter((note) => note.id !== event.note.id);
  return [...withoutChanged, event.note].sort((left, right) =>
    right.createdAt.localeCompare(left.createdAt) || left.id.localeCompare(right.id));
}

function foldRecording(recording: RecordingProjection | null, event: WhimEvent): RecordingProjection | null {
  if (event.type === 'recording.started') return event.recording;
  if (event.type === 'recording.stopped' || event.type === 'recording.discarded' || event.type === 'notes.reset') {
    return null;
  }
  return recording;
}
