import type { DeliveryStatus } from '@whim/expo-whim';
export function durationLabel(seconds: number): string {
  const value = Math.max(0, Math.floor(seconds));
  return `${Math.floor(value / 60)}:${String(value % 60).padStart(2, '0')}`;
}
export const statusLabel: Record<DeliveryStatus, string> = {
  setup_required: 'Setup required', queued: 'Queued', sending: 'Sending', sent: '✓ Sent', failed: '⚠ Failed',
};
export function dateLabel(value: string): string { return new Date(value).toLocaleString(); }
