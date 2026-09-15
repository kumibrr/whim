import { fireEvent, render, screen } from '@testing-library/react-native';
import type { NoteProjection } from '@whim/expo-whim';
import { TimelineScreen } from './TimelineScreen';

const notes: NoteProjection[] = [
  { schemaVersion: 1, id: 'old', title: 'Earlier failure', createdAt: '2026-09-04T12:00:00.000Z', durationSeconds: 42,
    source: 'apple_watch', status: 'failed', requiresReview: false, hasLocalAudio: true, localError: null, workflowError: null },
  { schemaVersion: 1, id: 'new', title: 'Latest thought', createdAt: '2026-09-05T12:00:00.000Z', durationSeconds: 65,
    source: 'iphone', status: 'sent', requiresReview: false, hasLocalAudio: false, localError: null, workflowError: null },
];

it('keeps failures in chronology and filters without hiding expired audio metadata', async () => {
  await render(<TimelineScreen notes={notes} onRecord={async () => {}} onOpen={() => {}} onRetry={async () => {}} onRetryAll={async () => {}} />);
  expect(screen.getAllByTestId(/^note-row-/).map(row => row.props.testID)).toEqual(['note-row-new', 'note-row-old']);
  expect(screen.getByText('Audio expired')).toBeOnTheScreen();
  expect(screen.getByText('Apple Watch · 0:42')).toBeOnTheScreen();
  expect(screen.getByRole('button', { name: 'Retry Earlier failure' })).toBeOnTheScreen();
  await fireEvent.press(screen.getByRole('button', { name: 'Failed filter' }));
  expect(screen.queryByText('Latest thought')).not.toBeOnTheScreen();
  expect(screen.getByText('⚠ Failed')).toBeOnTheScreen();
});

it('offers bulk retry from the Failed filter without changing configuration', async () => {
  let retries = 0;
  await render(<TimelineScreen notes={notes} onRecord={async () => {}} onOpen={() => {}} onRetry={async () => {}} onRetryAll={async () => { retries += 1; }} />);
  expect(screen.queryByRole('button', { name: 'Retry all failed Notes' })).not.toBeOnTheScreen();
  await fireEvent.press(screen.getByRole('button', { name: 'Failed filter' }));
  await fireEvent.press(screen.getByRole('button', { name: 'Retry all failed Notes' }));
  expect(retries).toBe(1);
});

it('includes metadata, delivery status and audio state in each Note button name', async () => {
  await render(<TimelineScreen notes={notes} onRecord={async () => {}} onOpen={() => {}} onRetry={async () => {}} onRetryAll={async () => {}} />);
  expect(screen.getByRole('button', { name: /Open Earlier failure.*2026.*Apple Watch.*0:42.*Failed/ })).toBeOnTheScreen();
  expect(screen.getByRole('button', { name: /Open Latest thought.*2026.*iPhone.*1:05.*Sent.*Audio expired/ })).toBeOnTheScreen();
});

it('announces recovered review requirements and unavailable audio with workflow errors', async () => {
  const recovered: NoteProjection = { ...notes[0], title: 'Recovered recording', requiresReview: true, hasLocalAudio: false, localError: 'unreadable', workflowError: 'delivery_preparation_failed' };
  await render(<TimelineScreen notes={[recovered]} onRecord={async () => {}} onOpen={() => {}} onRetry={async () => {}} onRetryAll={async () => {}} />);
  expect(screen.getByRole('button', { name: /Open Recovered recording.*Review required.*Audio unavailable.*Delivery needs attention/ })).toBeOnTheScreen();
});
