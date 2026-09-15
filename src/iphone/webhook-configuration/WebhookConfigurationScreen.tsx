import type { WhimClient, SettingsProjection, WebhookPatch, SecretPatch } from '@whim/expo-whim';
import { useState } from 'react';
import { Pressable, Switch, Text, TextInput, View } from 'react-native';
import { layout } from '../appearance/theme';

export function WebhookConfigurationScreen({ client, configuration, onSaved }: { client: WhimClient; configuration: SettingsProjection['webhook']; onSaved?(): void }) {
  const [endpoint, setEndpoint] = useState('');
  const [bearer, setBearer] = useState<SecretPatch>({ action: 'preserve' });
  const [hmac, setHmac] = useState<SecretPatch>({ action: 'preserve' });
  const [headers, setHeaders] = useState<WebhookPatch['customHeaders']>();
  const [newName, setNewName] = useState(''), [newValue, setNewValue] = useState('');
  const [newSecret, setNewSecret] = useState(true);
  const [message, setMessage] = useState<string | null>(null), [error, setError] = useState<string | null>(null);
  const [offerRetry, setOfferRetry] = useState(false), [pending, setPending] = useState(false);
  const existingHeaders = headers ?? configuration?.customHeaders.map(header => ({ ...header, action: 'preserve' as const })) ?? [];
  const dirty = endpoint !== '' || bearer.action !== 'preserve' || hmac.action !== 'preserve' || headers !== undefined || newName !== '' || newValue !== '';
  const clearOutcome = () => { setMessage(null); setOfferRetry(false); setError(null); };
  const edit = (change: () => void) => { clearOutcome(); change(); };
  const run = async (command: () => Promise<void>) => { setPending(true); clearOutcome(); try { await command(); } catch (e) { setError(e instanceof Error ? e.message : 'Configuration could not be saved.'); } finally { setPending(false); } };
  const button = (label: string, command: () => Promise<void>, disabled = false) => <Pressable accessibilityRole="button" disabled={pending || disabled} onPress={() => void run(command)} style={layout.button}><Text style={layout.text}>{label}</Text></Pressable>;
  const secretField = (label: string, value: SecretPatch, change: (patch: SecretPatch) => void, exists: boolean) => <View style={{ gap: 8 }}>
    <Text style={layout.text}>{label}{exists && value.action === 'preserve' ? ' · Saved ••••' : ''}</Text>
    <TextInput editable={!pending} testID={label === 'Bearer token' ? 'webhook-bearer-token' : 'webhook-hmac-secret'} accessibilityLabel={label} placeholder={exists ? 'Leave blank to preserve' : 'Optional'} secureTextEntry autoCapitalize="none" autoCorrect={false} value={value.action === 'replace' ? value.value : ''} onChangeText={text => edit(() => change(text ? { action: 'replace', value: text } : { action: 'preserve' }))} style={layout.input} />
    {exists && button(`Clear ${label.toLowerCase()}`, async () => { change({ action: 'clear' }); })}
    {value.action === 'clear' && <Text style={layout.secondary}>Will be removed when saved.</Text>}
  </View>;
  return <View testID="webhook-configuration" style={{ gap: 16 }}>
    <Text accessibilityRole="header" style={layout.heading}>Webhook</Text>
    {configuration && <Text style={layout.secondary}>Current destination: {configuration.destination.scheme}://{configuration.destination.host}{configuration.destination.port ? `:${configuration.destination.port}` : ''}{configuration.destination.path}</Text>}
    <TextInput editable={!pending} testID="webhook-url" accessibilityLabel="Webhook HTTPS URL" placeholder={configuration ? 'Leave blank to keep current URL' : 'https://your-workflow.example/whim'} autoCapitalize="none" autoCorrect={false} keyboardType="url" value={endpoint} onChangeText={value => edit(() => setEndpoint(value))} style={layout.input} />
    {secretField('Bearer token', bearer, setBearer, configuration?.hasBearerToken ?? false)}
    {secretField('HMAC secret', hmac, setHmac, configuration?.hasHMACSecret ?? false)}
    <Text style={layout.heading}>Custom headers</Text>
    {existingHeaders.map((header, index) => <View key={`${header.name}-${index}`} style={layout.row}><Text style={layout.text}>{header.name} · ••••</Text>{button(`Remove ${header.name}`, async () => setHeaders(existingHeaders.filter((_, i) => i !== index)))}</View>)}
    <Text style={layout.text}>Header name</Text>
    <TextInput editable={!pending} accessibilityLabel="Header name" autoCapitalize="none" value={newName} onChangeText={value => edit(() => setNewName(value))} style={layout.input} />
    <Text style={layout.text}>Header value</Text>
    <TextInput editable={!pending} accessibilityLabel="Header value" autoCapitalize="none" secureTextEntry value={newValue} onChangeText={value => edit(() => setNewValue(value))} style={layout.input} />
    <View style={layout.row}><Text style={layout.text}>Secret header</Text><Switch disabled={pending} accessibilityLabel="Secret header" value={newSecret} onValueChange={value => edit(() => setNewSecret(value))} /></View>
    {button('Add header', async () => { setHeaders([...existingHeaders, { name: newName, action: 'replace', value: newValue, isSecret: newSecret }]); setNewName(''); setNewValue(''); })}
    {button('Save webhook', async () => {
      const result = await client.patchWebhook({ ...(endpoint ? { endpoint } : {}), bearerToken: bearer, hmacSecret: hmac, ...(headers ? { customHeaders: headers } : {}) });
      setEndpoint(''); setBearer({ action: 'preserve' }); setHmac({ action: 'preserve' }); setHeaders(undefined);
      setMessage('Webhook saved. Test it to check delivery.'); setOfferRetry(result.failedCount + result.setupRequiredCount > 0); onSaved?.();
    })}
    {button('Test webhook', async () => { const result = await client.testWebhook(); setOfferRetry(result.passed); setMessage(result.passed ? result.idempotencyConfirmed ? 'Test passed. Idempotency confirmed.' : 'Test passed, but server-side idempotency could not be confirmed. Configure your server to deduplicate Note IDs.' : `Test failed${result.statusCode ? ` · HTTP ${result.statusCode}` : ''}. Check your configuration.`); }, dirty)}
    {dirty && <Text style={layout.secondary}>Save changes before testing.</Text>}
    {message && <Text accessibilityLiveRegion="polite" style={layout.text}>{message}</Text>}
    {error && <Text accessibilityRole="alert" style={layout.error}>{error}</Text>}
    {offerRetry && button('Retry unsent Notes', async () => { const count = await client.retryAllFailed(); setMessage(`${count} Notes offered for delivery.`); setOfferRetry(false); })}
  </View>;
}
