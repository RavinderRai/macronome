import 'react-native-get-random-values';  // Must be first!
import 'react-native-gesture-handler';
import React from 'react';
import { GestureHandlerRootView } from 'react-native-gesture-handler';
import { BottomSheetModalProvider } from '@gorhom/bottom-sheet';
import HomeScreen from './src/screens/HomeScreen';

export default function App() {
  return (
    <GestureHandlerRootView style={{ flex: 1 }}>
      <BottomSheetModalProvider>
        <HomeScreen />
      </BottomSheetModalProvider>
    </GestureHandlerRootView>
  );
}
