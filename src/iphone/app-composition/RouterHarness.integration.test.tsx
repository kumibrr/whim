import { renderRouter, screen } from 'expo-router/testing-library';

import { iphoneRoutes } from './RouterHarness';

describe('iPhone router', () => {
  it('opens Whim home at the root path', async () => {
    const router = renderRouter(iphoneRoutes);

    await router;

    expect(router.getPathname()).toBe('/');
    expect(screen.getByTestId('whim-home')).toBeOnTheScreen();
  });
});
