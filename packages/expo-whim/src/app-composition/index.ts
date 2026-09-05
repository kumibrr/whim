import { requireNativeModule } from 'expo-modules-core';

type ExpoWhimModule = {
  schemaVersion(): number;
};

const nativeModule = requireNativeModule<ExpoWhimModule>('ExpoWhim');

export function schemaVersion(): number {
  return nativeModule.schemaVersion();
}
