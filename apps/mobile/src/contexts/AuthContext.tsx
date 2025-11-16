/**
 * Auth Context
 * Provides authentication state and methods throughout the app
 */
import React, { createContext, useContext, useEffect, useState } from 'react';
import { useAuth, useUser } from '@clerk/clerk-expo';
import { tokenManager } from '../services/auth/tokenManager';

interface AuthContextType {
  isSignedIn: boolean;
  isLoading: boolean;
  userId: string | null;
  getToken: () => Promise<string | null>;
  signOut: () => Promise<void>;
}

const AuthContext = createContext<AuthContextType | undefined>(undefined);

export const AuthProvider: React.FC<{ children: React.ReactNode }> = ({ children }) => {
  const { isSignedIn, getToken: getClerkToken, signOut: clerkSignOut } = useAuth();
  const { user } = useUser();
  const [isLoading, setIsLoading] = useState(true);

  useEffect(() => {
    // Initial auth check
    setIsLoading(false);
  }, [isSignedIn]);

  /**
   * Get Clerk JWT token and store it securely
   */
  const getToken = async (): Promise<string | null> => {
    try {
      if (!isSignedIn) {
        return null;
      }

      // Get token from Clerk
      const token = await getClerkToken();
      
      if (token) {
        // Store token securely for API requests
        await tokenManager.saveToken(token);
        return token;
      }

      return null;
    } catch (error) {
      console.error('Failed to get token:', error);
      return null;
    }
  };

  /**
   * Sign out and clear stored token
   */
  const signOut = async (): Promise<void> => {
    try {
      await tokenManager.deleteToken();
      await clerkSignOut();
    } catch (error) {
      console.error('Failed to sign out:', error);
      throw error;
    }
  };

  // Update stored token when auth state changes
  useEffect(() => {
    if (isSignedIn) {
      getToken();
    } else {
      tokenManager.deleteToken().catch(console.error);
    }
  }, [isSignedIn]);

  const value: AuthContextType = {
    isSignedIn: isSignedIn ?? false,
    isLoading,
    userId: user?.id || null,
    getToken,
    signOut,
  };

  return <AuthContext.Provider value={value}>{children}</AuthContext.Provider>;
};

/**
 * Hook to use auth context
 */
export const useAuthContext = (): AuthContextType => {
  const context = useContext(AuthContext);
  if (context === undefined) {
    throw new Error('useAuthContext must be used within an AuthProvider');
  }
  return context;
};

