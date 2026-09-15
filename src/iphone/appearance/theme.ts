import { PlatformColor, StyleSheet } from 'react-native';

export const colors = {
  background: PlatformColor('systemBackground'),
  surface: PlatformColor('secondarySystemBackground'),
  text: PlatformColor('label'),
  secondary: PlatformColor('secondaryLabel'),
  failure: PlatformColor('systemRed'),
  accent: '#CC4939',
};
export const layout = StyleSheet.create({
  screen: { flex: 1, backgroundColor: colors.background },
  content: { padding: 24, paddingBottom: 110, gap: 20 },
  title: { color: colors.text, fontSize: 32, fontWeight: '700' },
  heading: { color: colors.text, fontSize: 22, fontWeight: '600' },
  text: { color: colors.text, fontSize: 17 },
  secondary: { color: colors.secondary, fontSize: 15 },
  error: { color: colors.failure, fontSize: 17 },
  row: { flexDirection: 'row', flexWrap: 'wrap', gap: 12, alignItems: 'center' },
  button: { paddingVertical: 14, paddingHorizontal: 16, minHeight: 48, borderRadius: 14, backgroundColor: colors.surface },
  input: { color: colors.text, borderColor: colors.secondary, borderWidth: 1, borderRadius: 10, padding: 12, fontSize: 17, minHeight: 48 },
});
