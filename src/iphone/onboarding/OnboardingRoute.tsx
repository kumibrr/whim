import { useRouter } from 'expo-router';
import { Text } from 'react-native';
import { useWhim } from '../app-composition/WhimProvider';
import { OnboardingScreen } from './OnboardingScreen';
import { SafeAreaView } from 'react-native-safe-area-context';
import { layout } from '../appearance/theme';
export default function OnboardingRoute() {
  const { client, settings, refresh } = useWhim();
  const router = useRouter();
  if (!settings) return <Text>Loading setup…</Text>;
  return <SafeAreaView style={layout.screen}><OnboardingScreen client={client} settings={settings} onRefresh={() => void refresh().catch(() => {})} onComplete={async () => { await refresh(); router.replace('/'); }} /></SafeAreaView>;
}
