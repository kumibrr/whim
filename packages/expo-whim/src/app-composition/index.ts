import { requireNativeModule } from 'expo-modules-core';
import { NativeWhimClient, type RawExpoWhimModule } from './NativeWhimClient';

const nativeModule = requireNativeModule<RawExpoWhimModule>('ExpoWhim');

export const whimClient = new NativeWhimClient(nativeModule);
export * from './NativeWhimClient';
export * from '../events/WhimEvent';
export * from '../notes/NoteProjection';
export * from '../preferences/PreferenceInput';
export * from '../recording/RecordingProjection';
export * from '../webhook-configuration/WebhookProjection';

export function schemaVersion(): number {
  return nativeModule.schemaVersion();
}
