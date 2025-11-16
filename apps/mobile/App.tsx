import 'react-native-get-random-values';  // Must be first!
import 'react-native-gesture-handler';
import React from 'react';
import { GestureHandlerRootView } from 'react-native-gesture-handler';
import { BottomSheetModalProvider } from '@gorhom/bottom-sheet';
import { ClerkProvider } from '@clerk/clerk-expo';
import { AuthProvider, useAuthContext } from './src/contexts/AuthContext';
import { ENV } from './src/utils/env';
import HomeScreen from './src/screens/HomeScreen';
import AuthScreen from './src/screens/auth/AuthScreen';
import { View, ActivityIndicator, StyleSheet } from 'react-native';
import { colors } from './src/theme/colors';

/**
 * Main App Content
 * Shows auth screen if not authenticated, otherwise shows main app
 */
function AppContent() {
  const { isSignedIn, isLoading } = useAuthContext();

  if (isLoading) {
    return (
      <View style={styles.loadingContainer}>
        <ActivityIndicator size="large" color={colors.accent.coral} />
      </View>
    );
  }

  if (!isSignedIn) {
    return <AuthScreen />;
  }

  return <HomeScreen />;
}

/**
 * Root App Component
 * Wraps app with Clerk and Auth providers
 */
export default function App() {
  return (
    <ClerkProvider publishableKey={ENV.clerkPublishableKey}>
      <AuthProvider>
        <GestureHandlerRootView style={{ flex: 1 }}>
          <BottomSheetModalProvider>
            <AppContent />
          </BottomSheetModalProvider>
        </GestureHandlerRootView>
      </AuthProvider>
    </ClerkProvider>
  );
}

const styles = StyleSheet.create({
  loadingContainer: {
    flex: 1,
    justifyContent: 'center',
    alignItems: 'center',
    backgroundColor: colors.background.primary,
  },
});
