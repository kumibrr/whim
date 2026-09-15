import type { PermissionKind, RetentionPolicy, SettingsProjection, WhimClient } from '@whim/expo-whim';
import { useState } from 'react';
import { Pressable, ScrollView, Switch, Text, TextInput, View } from 'react-native';
import { layout } from '../appearance/theme';
import { ConfirmationSheet } from '../destructive-actions/ConfirmationSheet';
import { WebhookConfigurationScreen } from '../webhook-configuration/WebhookConfigurationScreen';

const retentionChoices: [RetentionPolicy, string][] = [['immediately', 'Immediately'], ['one_day', '1 day'], ['seven_days', '7 days'], ['thirty_days', '30 days'], ['ninety_days', '90 days'], ['never', 'Never']];
export function PreferencesScreen({ client, settings, onRefresh, onReset }: { client: WhimClient; settings: SettingsProjection; onRefresh(): Promise<void>; onReset(): Promise<void> }) {
  const [confirm, setConfirm] = useState(false), [error, setError] = useState<string | null>(null);
  const [language, setLanguage] = useState(settings.preferences.transcriptionLocaleIdentifier ?? '');
  const [pending, setPending] = useState(false);
  const run = async (command: () => Promise<void>) => { setPending(true); setError(null); try { await command(); await onRefresh(); } catch (e) { setError(e instanceof Error ? e.message : 'Please try again.'); } finally { setPending(false); } };
  return <ScrollView testID="preferences" style={layout.screen} contentContainerStyle={layout.content} keyboardShouldPersistTaps="handled">
    <Text accessibilityRole="header" style={layout.title}>Settings</Text>
    <WebhookConfigurationScreen client={client} configuration={settings.webhook} onSaved={() => void onRefresh().catch(() => {})} />
    <Text accessibilityRole="header" style={layout.heading}>Keep audio after delivery</Text>
    <Text style={layout.secondary}>Unsent and recovered Notes are always kept until you delete them. Timeline metadata remains after audio expires.</Text>
    <View style={layout.row}>{retentionChoices.map(([value, label]) => <Pressable key={value} accessibilityRole="button" accessibilityLabel={`Keep audio: ${label}`} accessibilityState={{ selected: settings.preferences.retentionPolicy === value, disabled: pending }} disabled={pending} onPress={() => void run(() => client.updatePreferences({ ...settings.preferences, retentionPolicy: value }))} style={layout.button}><Text style={layout.text}>{label}</Text></Pressable>)}</View>
    <Text accessibilityRole="header" style={layout.heading}>On-device titles</Text>
    <View style={layout.row}><Text style={layout.text}>Transcription</Text><Switch accessibilityLabel="Transcription enabled" disabled={pending} value={settings.preferences.transcriptionEnabled} onValueChange={value => void run(() => client.updatePreferences({ ...settings.preferences, transcriptionEnabled: value }))} /></View>
    <Text style={layout.secondary}>Only on-device recognition is used. No full transcript is stored.</Text>
    <TextInput accessibilityLabel="Transcription language" placeholder="Device language (e.g. es-ES)" autoCapitalize="none" autoCorrect={false} value={language} onChangeText={setLanguage} style={layout.input} />
    <Pressable accessibilityRole="button" disabled={pending} style={layout.button} onPress={() => void run(() => client.updatePreferences({ ...settings.preferences, transcriptionLocaleIdentifier: language.trim() || null }))}><Text style={layout.text}>Save language</Text></Pressable>
    <Text accessibilityRole="header" style={layout.heading}>Permissions</Text>
    {(['microphone', 'speech', 'notifications'] as PermissionKind[]).map(kind => <View key={kind} style={{ gap: 8 }}>
      <Text style={layout.text}>{kind === 'microphone' ? 'Microphone' : kind === 'speech' ? 'Speech recognition' : 'Notifications'}: {settings.permissions[kind].replace('_', ' ')}</Text>
      {settings.permissions[kind] === 'not_determined' ? <Pressable accessibilityRole="button" disabled={pending} style={layout.button} onPress={() => void run(async () => { await client.requestPermission(kind); })}><Text style={layout.text}>Allow {kind}</Text></Pressable> : ['denied', 'restricted'].includes(settings.permissions[kind]) && <Pressable accessibilityRole="button" style={layout.button} onPress={() => void run(() => client.openSystemSettings())}><Text style={layout.text}>Open {kind} settings</Text></Pressable>}
    </View>)}
    <Text style={layout.secondary}>Choose whether notification previews show Note titles on the Lock Screen in system Settings → Notifications → Whim → Show Previews.</Text>
    <Pressable accessibilityRole="button" style={layout.button} onPress={() => void run(() => client.openSystemSettings())}><Text style={layout.text}>Notification preview settings</Text></Pressable>
    <Text accessibilityRole="header" style={layout.heading}>Apple Watch</Text>
    {settings.watch.availability === 'unavailable' && <Text style={layout.secondary}>Watch synchronization is unavailable in this build.</Text>}
    <Text style={layout.secondary}>A disconnected Watch cannot be erased immediately. Paired-device reset status is unavailable.</Text>
    {error && <Text accessibilityRole="alert" style={layout.error}>{error}</Text>}
    <Pressable accessibilityRole="button" style={layout.button} onPress={() => setConfirm(true)}><Text style={layout.error}>Reset Whim</Text></Pressable>
    {confirm && <ConfirmationSheet title="Reset Whim on this iPhone?" message="This removes all local audio, Notes, history, webhook configuration and credentials. It cannot revoke delivery accepted by your server or erase a disconnected Watch immediately." confirmLabel="Confirm reset" onCancel={() => setConfirm(false)} onConfirm={async () => { await client.reset(); await onReset(); }} />}
  </ScrollView>;
}
