import { fireEvent, render, screen } from '@testing-library/react-native';
import { noteFixture } from '../app-composition/WhimClient.test-support';
import { NoteDetailScreen } from './NoteDetailScreen';

it('offers Review and explicit Send for recovered Notes and protects the only local copy', async () => {
  const play = jest.fn(async () => {}), send = jest.fn(async () => {}), remove = jest.fn(async () => {});
  await render(<NoteDetailScreen note={noteFixture({ title: 'Recovered recording', requiresReview: true, status: 'failed' })} playing={false} onPlay={play} onStopPlayback={async () => {}} onRetry={async () => {}} onSend={send} onDelete={remove} />);
  expect(screen.queryByRole('button', { name: 'Retry' })).not.toBeOnTheScreen();
  await fireEvent.press(screen.getByRole('button', { name: 'Review recording' }));
  expect(play).toHaveBeenCalledTimes(1);
  await fireEvent.press(screen.getByRole('button', { name: 'Send Note' }));
  expect(send).toHaveBeenCalledTimes(1);
  await fireEvent.press(screen.getByRole('button', { name: 'Delete Note' }));
  expect(remove).not.toHaveBeenCalled();
  expect(screen.getByText(/only local copy/)).toBeOnTheScreen();
  await fireEvent.press(screen.getByRole('button', { name: 'Confirm delete' }));
  expect(remove).toHaveBeenCalledTimes(1);
});
