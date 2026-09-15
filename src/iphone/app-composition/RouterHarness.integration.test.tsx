import { renderRouter, screen } from 'expo-router/testing-library';
import { act, fireEvent } from '@testing-library/react-native';
import { Vibration } from 'react-native';
import Layout from '../app/_layout';
import { TestWhimClient, noteFixture } from './WhimClient.test-support';

jest.mock('@whim/expo-whim', () => ({ ...jest.requireActual('../../../packages/expo-whim/src/app-composition/NativeWhimClient'), whimClient: {} }));

import { iphoneRoutes } from './RouterHarness';

describe('iPhone router', () => {
  it('opens delivery detail, plays local audio, and immediately deletes a sent Note', async () => {
    const client = new TestWhimClient();
    client.settings.onboardingCompleted = true;
    client.notes = [noteFixture({ status: 'sent' })];
    await renderRouter({ ...iphoneRoutes, _layout: () => <Layout client={client} /> });
    await fireEvent.press(await screen.findByRole('button', { name: /^Open A thought,/ }));
    await fireEvent.press(await screen.findByRole('button', { name: 'Play Note' }));
    expect(await screen.findByText('Playing')).toBeOnTheScreen();
    await fireEvent.press(screen.getByRole('button', { name: 'Delete Note' }));
    expect(await screen.findByText('No Notes here yet. Capture a thought.')).toBeOnTheScreen();
    expect(client.calls).toEqual([`play:${noteFixture().id}`, `delete:${noteFixture().id}`]);
  });
  it('reads settings, persists retention and requires destructive Reset confirmation', async () => {
    const client = new TestWhimClient();
    client.settings.onboardingCompleted = true;
    client.settings.permissions.notifications = 'denied';
    await renderRouter({ ...iphoneRoutes, _layout: () => <Layout client={client} /> });
    await fireEvent.press(await screen.findByRole('button', { name: 'Settings' }));
    expect(await screen.findByText('Watch synchronization unavailable.')).toBeOnTheScreen();
    await fireEvent.press(screen.getByRole('button', { name: 'Keep audio: Never' }));
    expect(client.settings.preferences.retentionPolicy).toBe('never');
    expect(screen.getByText(/notification previews/)).toBeOnTheScreen();
    await fireEvent.press(screen.getByRole('button', { name: 'Reset Whim' }));
    expect(client.calls).not.toContain('reset');
    await fireEvent.press(screen.getByRole('button', { name: 'Confirm reset' }));
    expect(await screen.findByRole('button', { name: 'Get started' })).toBeOnTheScreen();
  });
  it('shows synchronized Watch availability and a pending remote reset', async () => {
    const client = new TestWhimClient();
    client.settings.onboardingCompleted = true;
    client.settings.watch = { availability: 'available', lastSynchronizedAt: '2026-09-15T09:00:00.000Z', resetState: 'pending' };
    await renderRouter({ ...iphoneRoutes, _layout: () => <Layout client={client} /> });
    await fireEvent.press(await screen.findByRole('button', { name: 'Settings' }));
    expect(await screen.findByText('Watch synchronization available.')).toBeOnTheScreen();
    expect(screen.getByText(/Last synchronized:/)).toBeOnTheScreen();
    expect(screen.getByText('Reset pending on Apple Watch. It will finish after reconnection.')).toBeOnTheScreen();
    client.settings = { ...client.settings, watch: { ...client.settings.watch, resetState: 'synchronized' } };
    await act(() => client.emit({ schemaVersion: 1, sequence: 1, type: 'settings.changed' }));
    expect(await screen.findByText('Reset completed on both devices.')).toBeOnTheScreen();
  });
  it('orders onboarding, skips webhook, requests microphone and returns a saved Note to timeline', async () => {
    const client = new TestWhimClient();
    await renderRouter({ ...iphoneRoutes, _layout: () => <Layout client={client} /> });
    await fireEvent.press(await screen.findByRole('button', { name: 'Get started' }));
    await fireEvent.press(screen.getByRole('button', { name: 'Skip webhook setup' }));
    expect(client.calls).not.toContain('permission:microphone');
    await fireEvent.press(screen.getByRole('button', { name: 'Allow microphone' }));
    await fireEvent.press(await screen.findByRole('button', { name: 'Record a Whim' }));
    expect(await screen.findByTestId('recorder-panel')).toBeOnTheScreen();
    await fireEvent.press(screen.getByRole('button', { name: 'Stop recording' }));
    expect(await screen.findByText('A thought')).toBeOnTheScreen();
    expect(screen.getByRole('button', { name: 'Enable on-device titles' })).toBeOnTheScreen();
    expect(client.calls).toEqual(['permission:microphone', 'completeOnboarding', 'start:iphone', 'stop']);
  });
  it('confirms an automatically finalized Note and offers optional permissions', async () => {
    const client = new TestWhimClient();
    client.settings.onboardingCompleted = true;
    client.settings.permissions.microphone = 'granted';
    const vibration = jest.spyOn(Vibration, 'vibrate').mockImplementation(() => {});
    await renderRouter({ ...iphoneRoutes, _layout: () => <Layout client={client} /> });
    await fireEvent.press(await screen.findByRole('button', { name: 'Record a Whim' }));
    vibration.mockClear();
    await act(() => { client.finalizeRecording(); });
    expect(await screen.findByText('Note saved')).toBeOnTheScreen();
    expect(screen.getByRole('button', { name: 'Enable on-device titles' })).toBeOnTheScreen();
    expect(vibration).toHaveBeenCalledTimes(1);
    expect(client.calls).not.toContain('stop');
    vibration.mockRestore();
  });
  it('does not offer denied optional permissions after automatic completion', async () => {
    const client = new TestWhimClient();
    client.settings.onboardingCompleted = true;
    client.settings.permissions = { microphone: 'granted', speech: 'denied', notifications: 'denied' };
    await renderRouter({ ...iphoneRoutes, _layout: () => <Layout client={client} /> });
    await fireEvent.press(await screen.findByRole('button', { name: 'Record a Whim' }));
    await act(() => { client.finalizeRecording(); });
    expect(await screen.findByText('Note saved')).toBeOnTheScreen();
    expect(screen.queryByRole('button', { name: 'Enable on-device titles' })).not.toBeOnTheScreen();
    expect(screen.queryByRole('button', { name: 'Enable delivery alerts' })).not.toBeOnTheScreen();
  });
  it('ignores delayed completion from a previous session after another recording is discarded', async () => {
    const client = new TestWhimClient();
    client.settings.onboardingCompleted = true;
    client.settings.permissions.microphone = 'granted';
    let finishLookup!: (value: ReturnType<typeof noteFixture>) => void;
    client.getNote = () => new Promise(resolve => { finishLookup = resolve; });
    await renderRouter({ ...iphoneRoutes, _layout: () => <Layout client={client} /> });
    await fireEvent.press(await screen.findByRole('button', { name: 'Record a Whim' }));
    await act(() => { client.finalizeRecording(); });
    await fireEvent.press(await screen.findByRole('button', { name: 'Record a Whim' }));
    await fireEvent.press(screen.getByRole('button', { name: 'Discard recording' }));
    await fireEvent.press(screen.getByRole('button', { name: 'Confirm discard' }));
    await act(() => { finishLookup(noteFixture()); });
    expect(screen.getByText('Recording discarded')).toBeOnTheScreen();
    expect(screen.queryByText('Note saved')).not.toBeOnTheScreen();
    expect(screen.queryByRole('button', { name: 'Enable on-device titles' })).not.toBeOnTheScreen();
  });
  it('opens Whim home at the root path', async () => {
    const client = new TestWhimClient();
    client.settings.onboardingCompleted = true;
    const router = renderRouter({ ...iphoneRoutes, _layout: () => <Layout client={client} /> });

    await router;

    expect(router.getPathname()).toBe('/');
    expect(screen.getByTestId('whim-home')).toBeOnTheScreen();
  });
});
