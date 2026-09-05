import { render } from '@testing-library/react-native';

import AppRoot from './AppRoot';

describe('Whim home', () => {
  it('exposes the home screen through its accessibility identifier', async () => {
    const view = await render(<AppRoot />);

    expect(view.getByTestId('whim-home')).toBeOnTheScreen();
  });
});
