import { useState } from 'react';
import { Pressable, ScrollView, Text, View } from 'react-native';
import { colors, layout } from '../appearance/theme';
import { ConfirmationSheet } from '../destructive-actions/ConfirmationSheet';
import { durationLabel } from '../timeline/format';
export type RecorderProps = { elapsedSeconds: number; peakPowerDBFS: number; maximumDurationSeconds: number; warningLeadSeconds: number; onStop(): Promise<void>; onDiscard(): Promise<void> };
export function RecorderPanel({ elapsedSeconds, peakPowerDBFS, maximumDurationSeconds, warningLeadSeconds, onStop, onDiscard }: RecorderProps) {
  const [confirmDiscard, setConfirmDiscard] = useState(false);
  const [pending, setPending] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const remaining = Math.max(0, maximumDurationSeconds - Math.floor(elapsedSeconds));
  const level = Math.max(0, Math.min(1, (peakPowerDBFS + 60) / 60));
  const stop = async () => { setPending(true); try { await onStop(); } catch (e) { setError(e instanceof Error ? e.message : 'Could not stop recording.'); } finally { setPending(false); } };
  return <ScrollView testID="recorder-panel" style={layout.screen} contentContainerStyle={layout.content}>
    <Text accessibilityRole="header" style={layout.title}>Recording</Text>
    <Text accessibilityLiveRegion="polite" style={[layout.title, { fontSize: 56, fontVariant: ['tabular-nums'] }]}>{durationLabel(elapsedSeconds)}</Text>
    <View accessible accessibilityLabel="Microphone level" accessibilityValue={{ text: `${Math.round(level * 100)} percent` }} style={{ height: 70, justifyContent: 'center' }}>
      <View style={{ height: 8 + level * 52, backgroundColor: colors.accent, borderRadius: 12 }} />
    </View>
    <View accessible accessibilityRole="progressbar" accessibilityLabel="Recording progress" accessibilityValue={{ min: 0, max: maximumDurationSeconds, now: Math.min(maximumDurationSeconds, elapsedSeconds), text: `${durationLabel(elapsedSeconds)} of ${durationLabel(maximumDurationSeconds)}` }} style={{ height: 8, backgroundColor: colors.surface }}><View style={{ height: 8, width: `${Math.min(100, elapsedSeconds / maximumDurationSeconds * 100)}%`, backgroundColor: colors.accent }} /></View>
    <Text style={remaining <= warningLeadSeconds ? layout.error : layout.secondary}>{remaining <= warningLeadSeconds ? `${remaining} seconds remaining` : `Up to ${maximumDurationSeconds / 60} minutes`}</Text>
    <Text style={layout.text}>Stop saves your Note and starts delivery.</Text>
    {error && <Text accessibilityRole="alert" style={layout.error}>{error}</Text>}
    <Pressable testID="stop-recording" accessibilityRole="button" accessibilityLabel="Stop recording" disabled={pending} onPress={() => void stop()} style={layout.button}><Text style={layout.heading}>■ Stop</Text></Pressable>
    <Pressable accessibilityRole="button" accessibilityLabel="Discard recording" onPress={() => setConfirmDiscard(true)} disabled={pending} style={layout.button}><Text style={layout.error}>Discard</Text></Pressable>
    {confirmDiscard && <ConfirmationSheet title="Discard this Recording Session?" message="This recording has not been saved. Discarding permanently removes it." confirmLabel="Confirm discard" cancelLabel="Keep recording" onCancel={() => setConfirmDiscard(false)} onConfirm={async () => { await onDiscard(); setConfirmDiscard(false); }} />}
  </ScrollView>;
}
