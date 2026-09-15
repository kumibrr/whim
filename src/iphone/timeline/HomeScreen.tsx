import { useEffect, useRef, useState } from 'react';
import { Redirect, useRouter } from 'expo-router';
import { Pressable, Text, View, Vibration } from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { useWhim } from '../app-composition/WhimProvider';
import { TimelineScreen } from '../timeline/TimelineScreen';
import { RecorderPanel } from '../recording/RecorderPanel';
import { layout } from '../appearance/theme';

export default function HomeScreen() {
  const { client, notes, recording, settings, error, refresh } = useWhim();
  const router = useRouter();
  const [elapsed, setElapsed] = useState(0), [peak, setPeak] = useState(-160);
  const [feedback, setFeedback] = useState(''), [contextual, setContextual] = useState(false);
  const starting = useRef(false);
  const activeNoteID = useRef(recording?.noteID);
  useEffect(() => { if (recording) activeNoteID.current = recording.noteID; }, [recording]);
  useEffect(() => {
    let mounted = true;
    let completionGeneration = 0;
    const subscription = client.subscribe(event => {
      if (event.type === 'recording.started') {
        completionGeneration += 1;
        activeNoteID.current = event.recording.noteID;
        setContextual(false);
      }
      if (event.type === 'recording.progress') {
        if (event.elapsedSeconds != null) setElapsed(event.elapsedSeconds);
        if (event.peakPowerDBFS != null) setPeak(event.peakPowerDBFS);
      }
      if (event.type === 'recording.stopped') {
        const generation = ++completionGeneration;
        const noteID = activeNoteID.current;
        activeNoteID.current = undefined;
        if (!noteID) return;
        Vibration.vibrate();
        setFeedback('Recording stopped');
        void client.getNote(noteID).then(note => {
          if (!mounted || generation !== completionGeneration || !note) return;
          setFeedback('Note saved');
          setContextual(true);
        }).catch(() => {});
        void refresh().catch(() => {});
      }
      if (event.type === 'recording.discarded' || event.type === 'notes.reset') {
        completionGeneration += 1;
        activeNoteID.current = undefined;
        setContextual(false);
        if (event.type === 'notes.reset') setFeedback('');
      }
    });
    return () => { mounted = false; subscription.remove(); };
  }, [client, refresh]);
  useEffect(() => { if (recording) setElapsed(Math.max(0, (Date.now() - Date.parse(recording.createdAt)) / 1000)); }, [recording?.sessionID]);
  if (!settings) return <SafeAreaView style={layout.screen}><Text style={layout.text}>{error?.message ?? 'Loading Whim…'}</Text><Pressable accessibilityRole="button" onPress={() => void refresh().catch(() => {})}><Text>Refresh</Text></Pressable></SafeAreaView>;
  if (!settings.onboardingCompleted) return <Redirect href="/onboarding" />;
  const start = async () => { if (starting.current || recording) return; starting.current = true; try { await client.startRecording('iphone'); Vibration.vibrate(); setFeedback('Recording started'); } finally { starting.current = false; } };
  return <SafeAreaView style={layout.screen}>
    <View style={[layout.row, { paddingHorizontal: 24 }]}><Pressable accessibilityRole="button" accessibilityLabel="Settings" style={layout.button} onPress={() => router.push('/settings')}><Text style={layout.text}>Settings</Text></Pressable></View>
    {feedback && <Text accessibilityLiveRegion="polite" style={[layout.secondary, { paddingHorizontal: 24 }]}>{feedback}</Text>}
    {recording ? <RecorderPanel elapsedSeconds={elapsed} peakPowerDBFS={peak} maximumDurationSeconds={recording.maximumDurationSeconds} warningLeadSeconds={recording.warningLeadSeconds} onStop={async () => { const note = await client.stopRecording(); if (!note) setFeedback('Short recording discarded'); }} onDiscard={async () => { await client.discardRecording(); setFeedback('Recording discarded'); }} /> : <TimelineScreen notes={notes} onRecord={start} onOpen={id => router.push(`/note/${id}`)} onRetry={id => client.retry(id)} onRetryAll={async () => { await client.retryAllFailed(); }} />}
    {contextual && !recording && (settings.permissions.speech === 'not_determined' || settings.permissions.notifications === 'not_determined') && <View style={{ padding: 20, gap: 8 }}>
      <Text style={layout.text}>Your Note is saved. Optional permissions help with titles and delivery alerts.</Text>
      {settings.permissions.speech === 'not_determined' && <Pressable accessibilityRole="button" style={layout.button} onPress={() => void client.requestPermission('speech').then(refresh).catch(() => setFeedback('Permission request failed. Try Settings.'))}><Text style={layout.text}>Enable on-device titles</Text></Pressable>}
      {settings.permissions.notifications === 'not_determined' && <Pressable accessibilityRole="button" style={layout.button} onPress={() => void client.requestPermission('notifications').then(refresh).catch(() => setFeedback('Permission request failed. Try Settings.'))}><Text style={layout.text}>Enable delivery alerts</Text></Pressable>}
      <Pressable accessibilityRole="button" onPress={() => setContextual(false)} style={layout.button}><Text style={layout.text}>Later</Text></Pressable>
    </View>}
    {settings.permissions.microphone !== 'granted' && <Pressable accessibilityRole="button" onPress={() => void client.openSystemSettings().catch(() => setFeedback('Open Settings to enable microphone access.'))} style={layout.button}><Text style={layout.text}>Microphone settings</Text></Pressable>}
  </SafeAreaView>;
}
