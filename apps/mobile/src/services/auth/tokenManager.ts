/**
 * Token Manager
 * Handles secure storage of Clerk JWT tokens
 */
import * as SecureStore from 'expo-secure-store';

const TOKEN_KEY = 'clerk_session_token';

export const tokenManager = {
  /**
   * Store Clerk session token securely
   */
  async saveToken(token: string): Promise<void> {
    try {
      await SecureStore.setItemAsync(TOKEN_KEY, token);
    } catch (error) {
      console.error('Failed to save token:', error);
      throw error;
    }
  },

  /**
   * Retrieve Clerk session token
   */
  async getToken(): Promise<string | null> {
    try {
      return await SecureStore.getItemAsync(TOKEN_KEY);
    } catch (error) {
      console.error('Failed to get token:', error);
      return null;
    }
  },

  /**
   * Remove Clerk session token
   */
  async deleteToken(): Promise<void> {
    try {
      await SecureStore.deleteItemAsync(TOKEN_KEY);
    } catch (error) {
      console.error('Failed to delete token:', error);
      throw error;
    }
  },
};

