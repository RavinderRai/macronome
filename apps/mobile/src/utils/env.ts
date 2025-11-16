// apps/mobile/src/utils/env.ts
import Constants from 'expo-constants';

export const ENV = {
  clerkPublishableKey: Constants.expoConfig?.extra?.clerkPublishableKey || '',
  apiBaseUrl: Constants.expoConfig?.extra?.apiBaseUrl || 'http://localhost:8000',
  isDev: Constants.expoConfig?.extra?.isDev ?? true,
};

