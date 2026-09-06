jest.mock('expo-modules-core', () => ({
  requireNativeModule: () => ({ schemaVersion: () => 1, addListener: () => ({ remove() {} }) }),
}));

import { schemaVersion } from './index';

describe('Expo Whim client', () => {
  it('exposes the native Whim schema version', () => {
    expect(schemaVersion()).toBe(1);
  });
});
