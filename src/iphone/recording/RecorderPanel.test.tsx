import { fireEvent, render, screen } from '@testing-library/react-native';
import { RecorderPanel } from './RecorderPanel';

it('announces remaining time and requires confirmation before destroying capture', async () => {
  const discard = jest.fn(async () => {});
  await render(<RecorderPanel elapsedSeconds={275} peakPowerDBFS={-12} maximumDurationSeconds={300} warningLeadSeconds={30} onStop={async () => {}} onDiscard={discard} />);
  expect(screen.getByText('4:35')).toBeOnTheScreen();
  expect(screen.getByText('25 seconds remaining')).toBeOnTheScreen();
  expect(screen.getByRole('progressbar', { name: 'Recording progress' })).toBeOnTheScreen();
  expect(screen.getByLabelText('Microphone level')).toBeOnTheScreen();
  await fireEvent.press(screen.getByRole('button', { name: 'Discard recording' }));
  expect(discard).not.toHaveBeenCalled();
  await fireEvent.press(screen.getByRole('button', { name: 'Keep recording' }));
  expect(screen.queryByRole('button', { name: 'Confirm discard' })).not.toBeOnTheScreen();
  await fireEvent.press(screen.getByRole('button', { name: 'Discard recording' }));
  await fireEvent.press(screen.getByRole('button', { name: 'Confirm discard' }));
  expect(discard).toHaveBeenCalledTimes(1);
});

it('uses the native recording limit for remaining time and progress', async () => {
  await render(<RecorderPanel elapsedSeconds={235} peakPowerDBFS={-40} maximumDurationSeconds={240} warningLeadSeconds={15} onStop={async () => {}} onDiscard={async () => {}} />);
  expect(screen.getByText('5 seconds remaining')).toBeOnTheScreen();
  expect(screen.getByRole('progressbar', { name: 'Recording progress' })).toHaveAccessibilityValue({ max: 240, now: 235 });
});
