import { useRouter } from 'expo-router';
import { Text } from 'react-native';
import { useWhim } from '../app-composition/WhimProvider';
import { PreferencesScreen } from './PreferencesScreen';
export default function SettingsRoute() {
  const { client, settings, refresh } = useWhim();
  const router = useRouter();
  if (!settings) return <Text>Loading settings…</Text>;
  return <PreferencesScreen client={client} settings={settings} onRefresh={refresh} onReset={async () => { await refresh(); router.replace('/onboarding'); }} />;
}
