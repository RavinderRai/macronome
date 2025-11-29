// apps/mobile/app.config.ts
import { ExpoConfig, ConfigContext } from 'expo/config';

export default ({ config }: ConfigContext): ExpoConfig => {
  // Read from environment variables
  const clerkPublishableKey = process.env.CLERK_PUBLISHABLE_KEY || '';
  const apiBaseUrl = process.env.API_BASE_URL || 'http://localhost:8000';
  const isDev = process.env.NODE_ENV !== 'production';

  return {
    ...config,
    name: 'Macronome',
    slug: 'macronome',
    version: '1.0.0',
    orientation: 'portrait',
    icon: './assets/icon.png',
    userInterfaceStyle: 'light',
    newArchEnabled: true,
    splash: {
      image: './assets/adaptive-icon.png',
      resizeMode: 'contain',
      backgroundColor: '#1E293B',
    },
    ios: {
      supportsTablet: true,
      bundleIdentifier: 'com.macronome.app',
    },
    android: {
      adaptiveIcon: {
        foregroundImage: './assets/adaptive-icon.png',
        backgroundColor: '#1E293B',
      },
      edgeToEdgeEnabled: true,
      predictiveBackGestureEnabled: false,
      package: 'com.macronome.app',
    },
    web: {
      favicon: './assets/favicon.png',
    },
    // Expose env vars to app via expo-constants
    extra: {
      eas: {
        projectId: "4565829b-a252-42f8-8836-02e5cc8e4038",
      },
      clerkPublishableKey,
      apiBaseUrl,
      isDev,
    },
  };
};