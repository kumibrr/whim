import type { PreferenceInput } from './PreferenceInput';
import type { WebhookProjection } from '../webhook-configuration/WebhookProjection';
export type PermissionKind = 'microphone' | 'speech' | 'notifications';
export type PermissionStatus = 'not_determined' | 'granted' | 'denied' | 'restricted' | 'unavailable';
export type SettingsProjection = {
  schemaVersion: 1;
  preferences: PreferenceInput;
  onboardingCompleted: boolean;
  permissions: Record<PermissionKind, PermissionStatus>;
  webhook: null | { revisionID: string; destination: WebhookProjection['destination']; hasBearerToken: boolean; hasHMACSecret: boolean; customHeaders: { name: string; isSecret: boolean }[] };
  watch: { availability: 'unavailable'; lastSynchronizedAt?: string | null; resetState: 'unavailable' };
};
export type SecretPatch = { action: 'preserve' | 'clear' } | { action: 'replace'; value: string };
export type WebhookPatch = { endpoint?: string; bearerToken?: SecretPatch; hmacSecret?: SecretPatch; customHeaders?: ({ name: string; isSecret: boolean } & SecretPatch)[] };
export type PlaybackProjection = { schemaVersion: 1; noteID: string; isPlaying: boolean; elapsedSeconds: number; durationSeconds: number };
