import { Text, View } from 'react-native';

export default function AppRoot() {
  return (
    <View testID="whim-home" accessibilityLabel="Whim home">
      <Text>Whim</Text>
    </View>
  );
}
