import type { SettingsProjection, WhimClient } from '@whim/expo-whim';
import { useState } from 'react';
import { Pressable, ScrollView, Text } from 'react-native';
import { layout } from '../appearance/theme';
import { WebhookConfigurationScreen } from '../webhook-configuration/WebhookConfigurationScreen';

export function OnboardingScreen({ client, settings, onComplete, onRefresh }: { client: WhimClient; settings: SettingsProjection; onComplete(): Promise<void>; onRefresh(): void }) {
  const [step, setStep] = useState(0), [error, setError] = useState<string | null>(null);
  const [pending, setPending] = useState(false);
  const run = async (command: () => Promise<void>) => { setPending(true); try { await command(); } catch (e) { setError(e instanceof Error ? e.message : 'Please try again.'); } finally { setPending(false); } };
  const button = (label: string, command: () => Promise<void>) => <Pressable accessibilityRole="button" disabled={pending} onPress={() => void run(command)} style={layout.button}><Text style={layout.text}>{label}</Text></Pressable>;
  return <ScrollView testID="onboarding" style={layout.screen} contentContainerStyle={layout.content} keyboardShouldPersistTaps="handled">
    <Text accessibilityRole="header" style={layout.title}>{step === 0 ? 'A place for your thoughts' : step === 1 ? 'Your workflow, directly' : 'Ready when inspiration strikes'}</Text>
    {step === 0 && <><Text style={layout.text}>Whim stores voice Notes locally on your iPhone and Apple Watch and delivers them directly to your webhook. No account, cloud storage, or analytics.</Text>{button('Get started', async () => setStep(1))}</>}
    {step === 1 && <><WebhookConfigurationScreen client={client} configuration={settings.webhook} onSaved={onRefresh} />{button('Continue to microphone', async () => setStep(2))}{button('Skip webhook setup', async () => setStep(2))}</>}
    {step === 2 && <>
      <Text style={layout.text}>Allow microphone access to capture voice Notes. You can finish setup and change permissions later in Settings.</Text>
      {settings.permissions.microphone === 'not_determined' && button('Allow microphone', async () => { await client.requestPermission('microphone'); await client.completeOnboarding(); await onComplete(); })}
      {['denied', 'restricted'].includes(settings.permissions.microphone) && <><Text style={layout.error}>Microphone access is denied. Enable it in system settings.</Text>{button('Open system settings', () => client.openSystemSettings())}</>}
      {button(settings.permissions.microphone === 'granted' ? 'Start using Whim' : 'Continue without microphone', async () => { await client.completeOnboarding(); await onComplete(); })}
    </>}
    {error && <Text accessibilityRole="alert" style={layout.error}>{error}</Text>}
  </ScrollView>;
}
