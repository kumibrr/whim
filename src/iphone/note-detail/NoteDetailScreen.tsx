import type { NoteDetailProjection } from '@whim/expo-whim';
import { useState } from 'react';
import { Pressable, ScrollView, Text, View } from 'react-native';
import { layout } from '../appearance/theme';
import { ConfirmationSheet } from '../destructive-actions/ConfirmationSheet';
import { dateLabel, durationLabel, statusLabel } from '../timeline/format';
export type DetailProps = { note: NoteDetailProjection; playing: boolean; onPlay(): Promise<void>; onStopPlayback(): Promise<void>; onRetry(): Promise<void>; onSend(): Promise<void>; onDelete(): Promise<void> };
export function NoteDetailScreen({ note, playing, onPlay, onStopPlayback, onRetry, onSend, onDelete }: DetailProps) {
  const [confirmDelete, setConfirmDelete] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [pending, setPending] = useState(false);
  const run = async (command: () => Promise<void>) => { setPending(true); setError(null); try { await command(); } catch (e) { setError(e instanceof Error ? e.message : 'Please try again.'); } finally { setPending(false); } };
  const action = (label: string, command: () => Promise<void>) => <Pressable key={label} accessibilityRole="button" accessibilityLabel={label} disabled={pending} onPress={() => void run(command)} style={layout.button}><Text style={layout.text}>{label}</Text></Pressable>;
  return <ScrollView testID="note-detail" style={layout.screen} contentContainerStyle={layout.content}>
    <Text accessibilityRole="header" style={layout.title}>{note.title}</Text>
    <Text style={layout.secondary}>{dateLabel(note.createdAt)}</Text>
    <Text style={layout.text}>{note.source === 'iphone' ? 'iPhone' : 'Apple Watch'} · {durationLabel(note.durationSeconds)}</Text>
    <Text style={note.status === 'failed' ? layout.error : layout.heading}>{note.requiresReview ? 'Review required' : statusLabel[note.status]}</Text>
    {note.hasLocalAudio ? action(playing ? 'Stop playback' : note.requiresReview ? 'Review recording' : 'Play Note', playing ? onStopPlayback : onPlay) : <Text style={layout.secondary}>{note.localError ? 'Audio unavailable' : 'Audio expired'}</Text>}
    {playing && <Text accessibilityLiveRegion="polite" style={layout.text}>Playing</Text>}
    {note.localError && <Text style={layout.error}>Local audio error: {note.localError}</Text>}
    {note.workflowError && <Text style={layout.error}>Delivery could not continue. Your Note is preserved.</Text>}
    {note.requiresReview ? <><Text style={layout.text}>Review this recovered Note, then choose Send or Delete. It will not send automatically.</Text>{note.hasLocalAudio && action('Send Note', onSend)}</> : ['failed', 'queued', 'setup_required'].includes(note.status) && action('Retry', onRetry)}
    {error && <Text accessibilityRole="alert" style={layout.error}>{error}</Text>}
    <Text accessibilityRole="header" style={layout.heading}>Delivery details</Text>
    {note.attempts.length === 0 && <Text style={layout.secondary}>No Attempts yet.</Text>}
    {note.attempts.map(attempt => <View key={attempt.id} style={{ gap: 6 }}>
      <Text style={layout.text}>{attempt.outcome === 'sent' ? '✓ Sent' : attempt.outcome === 'failed' ? '⚠ Failed' : 'Sending'}{attempt.responseStatusCode ? ` · HTTP ${attempt.responseStatusCode}` : ''}</Text>
      <Text style={layout.secondary}>{attempt.destination.scheme}://{attempt.destination.host}{attempt.destination.port ? `:${attempt.destination.port}` : ''}{attempt.destination.path}</Text>
      <Text style={layout.secondary}>{dateLabel(attempt.startedAt)} · {attempt.device === 'iphone' ? 'iPhone' : 'Apple Watch'}</Text>
      {attempt.failureReason && <Text style={layout.error}>{attempt.failureReason === 'network' ? 'The destination could not be reached.' : 'The destination rejected this Attempt.'}</Text>}
      <Text selectable style={layout.secondary}>Configuration Revision: {attempt.configurationRevisionID}</Text>
    </View>)}
    {action('Delete Note', async () => { if (note.status === 'sent' && !note.requiresReview) await onDelete(); else setConfirmDelete(true); })}
    {confirmDelete && <ConfirmationSheet title="Delete this Note?" message="This may be the only local copy. Deleting cannot revoke delivery already accepted by your server." confirmLabel="Confirm delete" onCancel={() => setConfirmDelete(false)} onConfirm={onDelete} />}
  </ScrollView>;
}
