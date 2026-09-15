import { Stack } from 'expo-router';
import type { WhimClient } from '@whim/expo-whim';
import { WhimProvider } from './WhimProvider';

export default function RootLayout({ client }: { client?: WhimClient }) {
  return <WhimProvider client={client}><Stack screenOptions={{ headerShown: true, title: 'Whim', animation: 'none' }}><Stack.Screen name="index" options={{ headerShown: false }} /><Stack.Screen name="onboarding" options={{ headerShown: false }} /></Stack></WhimProvider>;
}
