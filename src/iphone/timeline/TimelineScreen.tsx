import type { NoteProjection } from '@whim/expo-whim';
import { useState } from 'react';
import { Pressable, ScrollView, Text, View } from 'react-native';
import { colors, layout } from '../appearance/theme';
import { NoteRow } from './NoteRow';
export type TimelineProps = { notes: NoteProjection[]; onRecord(): Promise<void>; onOpen(id: string): void; onRetry(id: string): Promise<void>; onRetryAll(): Promise<void> };
export function TimelineScreen({ notes, onRecord, onOpen, onRetry, onRetryAll }: TimelineProps) {
  const [filter, setFilter] = useState('All');
  const [error, setError] = useState<string | null>(null);
  const run = (command: () => Promise<void>) => { setError(null); void command().catch(e => setError(e.message)); };
  const visible = [...notes].sort((a, b) => b.createdAt.localeCompare(a.createdAt) || a.id.localeCompare(b.id))
    .filter(note => filter === 'All' || (filter === 'Queued' ? ['queued', 'setup_required', 'sending'].includes(note.status) : note.status === filter.toLowerCase()));
  return <View testID="whim-home" style={layout.screen}>
    <ScrollView contentContainerStyle={layout.content}>
      <Text accessibilityRole="header" style={layout.title}>Your Whims</Text>
      <View style={layout.row}>{['All', 'Queued', 'Failed', 'Sent'].map(value => <Pressable key={value} accessibilityRole="button" accessibilityLabel={`${value} filter`} accessibilityState={{ selected: value === filter }} onPress={() => setFilter(value)} style={layout.button}><Text style={layout.text}>{value}</Text></Pressable>)}</View>
      {filter === 'Failed' && visible.some(note => !note.requiresReview) && <Pressable accessibilityRole="button" onPress={() => run(onRetryAll)} style={layout.button}><Text style={layout.text}>Retry all failed Notes</Text></Pressable>}
      {error && <Text accessibilityRole="alert" style={layout.error}>{error}</Text>}
      {visible.length === 0 && <Text style={layout.secondary}>No Notes here yet. Capture a thought.</Text>}
      {visible.map(note => <NoteRow key={note.id} note={note} onOpen={onOpen} onRetry={id => run(() => onRetry(id))} />)}
    </ScrollView>
    <Pressable testID="record-button" accessibilityRole="button" accessibilityLabel="Record a Whim" onPress={() => run(onRecord)} style={{ position: 'absolute', bottom: 24, alignSelf: 'center', backgroundColor: colors.accent, padding: 20, borderRadius: 32 }}><Text style={{ color: '#FFFFFF', fontSize: 20, fontWeight: '600' }}>● Record</Text></Pressable>
  </View>;
}
