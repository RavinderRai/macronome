/**
 * Auth Context
 * Provides authentication state and methods throughout the app
 */
import React, { createContext, useContext, useEffect, useState } from 'react';
import { useAuth, useUser } from '@clerk/clerk-expo';
import { tokenManager } from '../services/auth/tokenManager';
import { getUserStatus, initializeUser } from '../services/api/users';
import { setClerkTokenGetter } from '../services/api/client';

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

  // Register token getter with API client for automatic refresh on 401
  useEffect(() => {
    setClerkTokenGetter(async () => {
      if (!isSignedIn) return null;
      try {
        return await getClerkToken();
      } catch (error) {
        console.error('Failed to get Clerk token:', error);
        return null;
      }
    });
  }, [isSignedIn, getClerkToken]);

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

  // Update stored token and check initialization when auth state changes
  useEffect(() => {
    const handleAuthChange = async () => {
      if (isSignedIn) {
        await getToken();
        
        // Check if user is initialized in Supabase
        try {
          const status = await getUserStatus();
          
          if (!status.is_initialized) {
            console.log('User not initialized, initializing now...');
            await initializeUser();
            console.log('✅ User initialized successfully');
          }
        } catch (error) {
          console.error('Failed to check/initialize user:', error);
          // Continue anyway - user can be initialized lazily
        }
      } else {
        tokenManager.deleteToken().catch(console.error);
      }
    };
    
    handleAuthChange();
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

