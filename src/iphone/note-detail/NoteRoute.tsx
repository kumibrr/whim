import type { NoteDetailProjection, PlaybackProjection } from '@whim/expo-whim';
import { useLocalSearchParams, useRouter } from 'expo-router';
import { useEffect, useState } from 'react';
import { Pressable, Text, View } from 'react-native';
import { useWhim } from '../app-composition/WhimProvider';
import { NoteDetailScreen } from './NoteDetailScreen';
import { layout } from '../appearance/theme';

export default function NoteRoute() {
  const { id } = useLocalSearchParams<{ id: string }>();
  const { client, notes, playback: snapshot, refresh } = useWhim();
  const router = useRouter();
  const [note, setNote] = useState<NoteDetailProjection | null>(null);
  const [playback, setPlayback] = useState<PlaybackProjection | null>(snapshot);
  const [error, setError] = useState<string | null>(null);
  useEffect(() => { setPlayback(snapshot); }, [snapshot]);
  useEffect(() => {
    let active = true;
    void client.getNote(id).then(value => { if (active) setNote(value); }).catch(() => { if (active) setError('This Note could not be loaded.'); });
    return () => { active = false; };
  }, [client, id, notes]);
  useEffect(() => {
    let active = true;
    const timer = setInterval(() => { void client.getPlayback().then(value => { if (active) setPlayback(value); }).catch(() => {}); }, 500);
    return () => { active = false; clearInterval(timer); void client.stopPlayback().catch(() => {}); };
  }, [client]);
  if (!note) return <View style={[layout.screen, layout.content]}><Text style={layout.text}>{error ?? 'This Note is unavailable.'}</Text><Pressable accessibilityRole="button" onPress={() => router.replace('/')}><Text style={layout.text}>Return to timeline</Text></Pressable></View>;
  return <NoteDetailScreen note={note} playing={playback?.noteID === id && playback.isPlaying}
    onPlay={async () => { setPlayback(await client.playNote(id)); }} onStopPlayback={async () => { await client.stopPlayback(); setPlayback(null); }}
    onRetry={async () => { await client.retry(id); await refresh(); }} onSend={async () => { await client.sendRecovered(id); await refresh(); }}
    onDelete={async () => { await client.deleteNote(id); router.replace('/'); }} />;
}
