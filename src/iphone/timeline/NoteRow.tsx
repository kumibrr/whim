import type { NoteProjection } from '@whim/expo-whim';
import { Pressable, Text, View } from 'react-native';
import { colors, layout } from '../appearance/theme';
import { dateLabel, durationLabel, statusLabel } from './format';

export function NoteRow({ note, onOpen, onRetry }: { note: NoteProjection; onOpen(id: string): void; onRetry(id: string): void }) {
  const source = note.source === 'iphone' ? 'iPhone' : 'Apple Watch';
  const status = note.requiresReview ? '⚠ Review required' : statusLabel[note.status];
  const audioState = note.hasLocalAudio ? null : note.localError ? 'Audio unavailable' : 'Audio expired';
  const accessibleName = [
    `Open ${note.title}`, dateLabel(note.createdAt), source, durationLabel(note.durationSeconds), status,
    audioState, note.workflowError ? 'Delivery needs attention' : null,
  ].filter(Boolean).join(', ');
  return <View testID={`note-row-${note.id}`} style={{ paddingVertical: 16, gap: 8, borderBottomWidth: 0.5, borderColor: colors.secondary }}>
    <Pressable accessibilityRole="button" accessibilityLabel={accessibleName} onPress={() => onOpen(note.id)} style={{ gap: 8 }}>
      <Text style={layout.heading}>{note.title}</Text>
      <Text style={layout.secondary}>{dateLabel(note.createdAt)}</Text>
      <Text style={layout.secondary}>{source} · {durationLabel(note.durationSeconds)}</Text>
      <Text style={note.status === 'failed' ? layout.error : layout.text}>{status}</Text>
      {audioState && <Text style={layout.secondary}>{audioState}</Text>}
      {note.workflowError && <Text style={layout.error}>Delivery needs attention</Text>}
    </Pressable>
    {note.status === 'failed' && !note.requiresReview && <Pressable accessibilityRole="button" accessibilityLabel={`Retry ${note.title}`} onPress={() => onRetry(note.id)} style={layout.button}><Text style={layout.text}>Retry</Text></Pressable>}
  </View>;
}
