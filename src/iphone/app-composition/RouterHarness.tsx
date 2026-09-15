import Layout from '../app/_layout';
import Index from '../app/index';
import Onboarding from '../app/onboarding';
import Settings from '../app/settings';
import Note from '../app/note/[id]';

export const iphoneRoutes = {
  _layout: Layout,
  index: Index,
  onboarding: Onboarding,
  settings: Settings,
  'note/[id]': Note,
};
