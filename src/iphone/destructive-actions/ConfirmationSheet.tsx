import { useState } from 'react';
import { Modal, Pressable, Text, View } from 'react-native';
import { layout } from '../appearance/theme';

export function ConfirmationSheet({ title, message, confirmLabel, cancelLabel = 'Cancel', onConfirm, onCancel }: {
  title: string; message: string; confirmLabel: string; cancelLabel?: string; onConfirm(): Promise<void>; onCancel(): void;
}) {
  const [pending, setPending] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const confirm = async () => { setPending(true); try { await onConfirm(); } catch (e) { setError(e instanceof Error ? e.message : 'Please try again.'); } finally { setPending(false); } };
  return <Modal transparent animationType="none" onRequestClose={onCancel}>
    <View style={{ flex: 1, backgroundColor: '#00000088', justifyContent: 'center', padding: 24 }}>
      <View accessibilityViewIsModal style={[layout.content, layout.screen, { flex: 0, borderRadius: 20, paddingBottom: 24 }]}>
        <Text accessibilityRole="header" style={layout.heading}>{title}</Text>
        <Text style={layout.text}>{message}</Text>
        {error && <Text accessibilityRole="alert" style={layout.error}>{error}</Text>}
        <Pressable accessibilityRole="button" disabled={pending} accessibilityState={{ disabled: pending }} onPress={() => void confirm()} style={layout.button}><Text style={layout.error}>{confirmLabel}</Text></Pressable>
        <Pressable accessibilityRole="button" disabled={pending} onPress={onCancel} style={layout.button}><Text style={layout.text}>{cancelLabel}</Text></Pressable>
      </View>
    </View>
  </Modal>;
}
