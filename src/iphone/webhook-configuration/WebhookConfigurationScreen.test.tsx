import { fireEvent, render, screen } from '@testing-library/react-native';
import { TestWhimClient } from '../app-composition/WhimClient.test-support';
import { WebhookConfigurationScreen } from './WebhookConfigurationScreen';

it('preserves masked secrets on save and offers retry after an idempotency-unconfirmed test', async () => {
  const client = new TestWhimClient();
  client.settings.webhook = { revisionID: 'revision', destination: { scheme: 'https', host: 'example.com', port: null, path: '/whim' }, hasBearerToken: true, hasHMACSecret: true, customHeaders: [{ name: 'X-Secret', isSecret: true }] };
  await render(<WebhookConfigurationScreen client={client} configuration={client.settings.webhook} />);
  await fireEvent.press(screen.getByRole('button', { name: 'Save webhook' }));
  expect(client.patches[0]).toEqual({ bearerToken: { action: 'preserve' }, hmacSecret: { action: 'preserve' } });
  await fireEvent.press(screen.getByRole('button', { name: 'Test webhook' }));
  expect(screen.getByText(/idempotency could not be confirmed/)).toBeOnTheScreen();
  await fireEvent.press(screen.getByRole('button', { name: 'Retry unsent Notes' }));
  expect(client.calls).toContain('retryAllFailed');
});

it('requires saving changed configuration before testing the saved destination', async () => {
  const client = new TestWhimClient();
  await render(<WebhookConfigurationScreen client={client} configuration={null} />);
  await fireEvent.press(screen.getByRole('button', { name: 'Test webhook' }));
  await fireEvent.changeText(screen.getByLabelText('Webhook HTTPS URL'), 'https://new.example/whim');
  expect(screen.getByRole('button', { name: 'Test webhook' })).toBeDisabled();
  expect(screen.getByText('Save changes before testing.')).toBeOnTheScreen();
  expect(screen.queryByText(/Test passed/)).not.toBeOnTheScreen();
  expect(screen.queryByRole('button', { name: 'Retry unsent Notes' })).not.toBeOnTheScreen();
});

it('clears old success when a subsequent test throws', async () => {
  const client = new TestWhimClient();
  await render(<WebhookConfigurationScreen client={client} configuration={null} />);
  await fireEvent.press(screen.getByRole('button', { name: 'Test webhook' }));
  client.testWebhook = async () => { throw new Error('Test could not run.'); };
  await fireEvent.press(screen.getByRole('button', { name: 'Test webhook' }));
  expect(screen.getByText('Test could not run.')).toBeOnTheScreen();
  expect(screen.queryByText(/Test passed/)).not.toBeOnTheScreen();
  expect(screen.queryByRole('button', { name: 'Retry unsent Notes' })).not.toBeOnTheScreen();
});

it('visibly labels both custom header inputs while preserving accessible input names', async () => {
  await render(<WebhookConfigurationScreen client={new TestWhimClient()} configuration={null} />);
  expect(screen.getByText('Header name')).toBeOnTheScreen();
  expect(screen.getByText('Header value')).toBeOnTheScreen();
  expect(screen.getByLabelText('Header name')).toBeOnTheScreen();
  expect(screen.getByLabelText('Header value')).toBeOnTheScreen();
});
