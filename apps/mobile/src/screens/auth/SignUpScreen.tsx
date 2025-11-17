/**
 * Sign Up Screen
 * Clerk-powered sign up with email
 */
import React, { useState, useEffect } from 'react';
import {
  View,
  Text,
  TextInput,
  TouchableOpacity,
  StyleSheet,
  Alert,
  KeyboardAvoidingView,
  Platform,
} from 'react-native';
import { useSignUp, useAuth } from '@clerk/clerk-expo';
import { colors } from '../../theme/colors';
import { initializeUser } from '../../services/api/users';
import { ENV } from '../../utils/env';
import { tokenManager } from '../../services/auth/tokenManager';

export default function SignUpScreen() {
  const { signUp, setActive, isLoaded } = useSignUp();
  const { getToken: getClerkToken } = useAuth();
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [isLoading, setIsLoading] = useState(false);
  const [needsEmailVerification, setNeedsEmailVerification] = useState(false);
  const [verificationCode, setVerificationCode] = useState('');

  // Debug: Log configuration on mount
  useEffect(() => {
    console.log('=== SignUpScreen Configuration ===');
    console.log('Clerk isLoaded:', isLoaded);
    console.log('API Base URL:', ENV.apiBaseUrl);
    console.log('Clerk Key configured:', !!ENV.clerkPublishableKey);
    console.log('==================================');
  }, [isLoaded]);

  const activateSession = async (sessionId: string) => {
    if (!setActive) {
      throw new Error('setActive is not available');
    }
    
    try {
      console.log('Setting active session...');
      await setActive({ session: sessionId });
      console.log('Session activated successfully');
      
      // Get token directly from Clerk and save it before initializing
      // Wait a moment for Clerk to fully activate the session and generate token
      console.log('Waiting for session to be fully active...');
      await new Promise(resolve => setTimeout(resolve, 1000)); // Wait 1 second
      
      let tokenRetries = 0;
      let token: string | null = null;
      const maxRetries = 5;
      
      while (!token && tokenRetries < maxRetries) {
        try {
          console.log(`Getting token from Clerk (attempt ${tokenRetries + 1}/${maxRetries})...`);
          token = await getClerkToken();
          
          if (token) {
            console.log('Token retrieved, saving to secure storage...');
            await tokenManager.saveToken(token);
            console.log('Token saved successfully');
            console.log('Token preview:', token.substring(0, 50) + '...');
            break;
          } else {
            console.log('No token available yet, waiting...');
            await new Promise(resolve => setTimeout(resolve, 500));
            tokenRetries++;
          }
        } catch (tokenError: any) {
          console.error('Failed to get token:', tokenError);
          tokenRetries++;
          if (tokenRetries < maxRetries) {
            await new Promise(resolve => setTimeout(resolve, 500));
          }
        }
      }
      
      if (!token) {
        console.warn('⚠️ Could not get token after retries - initialization will be handled by AuthContext');
      }
      
      // Initialize user in Supabase (create preferences, chat session, etc.)
      // Only try if we have a token
      if (token) {
        try {
          console.log('Initializing user in Supabase...');
          await initializeUser();
          console.log('✅ User initialized successfully');
        } catch (error: any) {
          console.error('Failed to initialize user:', error);
          console.error('Error details:', JSON.stringify(error.response?.data || error.message));
          // Don't block sign-up if initialization fails
          // User can be initialized lazily on first API call (AuthContext will handle it)
        }
      } else {
        console.log('Skipping initialization - will be handled by AuthContext when token is ready');
      }
    } catch (error: any) {
      console.error('Failed to activate session:', error);
      throw error;
    }
  };

  const handleSignUp = async () => {
    console.log('handleSignUp called');
    
    if (!isLoaded) {
      console.log('Clerk not loaded yet');
      return;
    }

    if (!email || !password) {
      Alert.alert('Error', 'Please enter both email and password');
      return;
    }

    if (password.length < 8) {
      Alert.alert('Error', 'Password must be at least 8 characters');
      return;
    }

    setIsLoading(true);

    try {
      console.log('Creating Clerk account...');
      const result = await signUp.create({
        emailAddress: email,
        password,
      });

      console.log('Clerk account created, status:', result.status);
      console.log('Created session ID:', result.createdSessionId);
      console.log('SignUp status:', signUp.status);

      // Check if email verification is required
      // If no session ID is created, verification is likely required
      // Also check signUp.status for verification requirements
      const needsVerification = !result.createdSessionId || 
                                 signUp.status === 'missing_requirements';

      if (needsVerification && signUp) {
        // Email verification is required
        try {
          console.log('Preparing email verification...');
          await signUp.prepareEmailAddressVerification({ strategy: 'email_code' });
          console.log('Email verification code sent');
          setNeedsEmailVerification(true);
          Alert.alert(
            'Email Verification Required',
            `A verification code has been sent to ${email}. Please enter the code below to complete your sign-up.`,
            [{ text: 'OK' }]
          );
        } catch (verifyError: any) {
          console.error('Failed to prepare email verification:', verifyError);
          Alert.alert('Error', 'Failed to send verification code. Please try again.');
        }
      } else if (result.createdSessionId) {
        // No verification needed (if "Verify at sign-up" is disabled in Clerk)
        // Activate session immediately
        console.log('No verification required, activating session...');
        await activateSession(result.createdSessionId);
      } else {
        console.log('No session ID found, cannot activate session');
        Alert.alert('Error', 'Could not create session. Please try again.');
      }
    } catch (error: any) {
      console.error('Sign up error:', error);
      console.error('Error details:', JSON.stringify(error.errors || error.message));
      Alert.alert('Sign Up Failed', error.errors?.[0]?.message || error.message || 'An error occurred');
    } finally {
      setIsLoading(false);
    }
  };

  const handleVerifyEmail = async () => {
    if (!verificationCode || verificationCode.length < 6) {
      Alert.alert('Error', 'Please enter the 6-digit verification code');
      return;
    }

    if (!signUp) {
      Alert.alert('Error', 'Sign up session not available. Please try again.');
      return;
    }

    setIsLoading(true);

    try {
      console.log('Attempting to verify email code...');
      const result = await signUp.attemptEmailAddressVerification({
        code: verificationCode,
      });

      console.log('Verification result status:', result.status);
      console.log('Created session ID:', result.createdSessionId);

      if (result.createdSessionId) {
        console.log('Email verified, activating session...');
        await activateSession(result.createdSessionId);
        setNeedsEmailVerification(false);
        setVerificationCode('');
        // Navigation will be handled by auth state change
      } else if (result.status === 'complete') {
        if (signUp.createdSessionId) {
          await activateSession(signUp.createdSessionId);
          setNeedsEmailVerification(false);
          setVerificationCode('');
        } else {
          Alert.alert('Error', 'Verification complete but no session available. Please try again.');
        }
      } else {
        Alert.alert('Error', `Verification incomplete. Status: ${result.status}`);
      }
    } catch (error: any) {
      console.error('Email verification error:', error);
      Alert.alert(
        'Verification Failed',
        error.errors?.[0]?.message || error.message || 'Invalid verification code. Please try again.'
      );
    } finally {
      setIsLoading(false);
    }
  };

  return (
    <KeyboardAvoidingView
      style={styles.container}
      behavior={Platform.OS === 'ios' ? 'padding' : 'height'}
    >
      <View style={styles.content}>
        <Text style={styles.title}>Create Account</Text>
        <Text style={styles.subtitle}>Sign up to start using Macronome</Text>

        <View style={styles.form}>
          {!needsEmailVerification ? (
            <>
              <TextInput
                style={styles.input}
                placeholder="Email"
                placeholderTextColor={colors.text.muted}
                value={email}
                onChangeText={setEmail}
                keyboardType="email-address"
                autoCapitalize="none"
                autoComplete="email"
                editable={!isLoading}
              />

              <TextInput
                style={styles.input}
                placeholder="Password (min 8 characters)"
                placeholderTextColor={colors.text.muted}
                value={password}
                onChangeText={setPassword}
                secureTextEntry
                autoCapitalize="none"
                editable={!isLoading}
              />

              <TouchableOpacity
                style={[styles.button, isLoading && styles.buttonDisabled]}
                onPress={handleSignUp}
                disabled={isLoading || !isLoaded}
              >
                <Text style={styles.buttonText}>
                  {isLoading ? 'Creating account...' : 'Sign Up'}
                </Text>
              </TouchableOpacity>
            </>
          ) : (
            <>
              <Text style={styles.verificationText}>
                Enter the verification code sent to {email}
              </Text>

              <TextInput
                style={styles.input}
                placeholder="Verification Code"
                placeholderTextColor={colors.text.muted}
                value={verificationCode}
                onChangeText={setVerificationCode}
                keyboardType="number-pad"
                maxLength={6}
                editable={!isLoading}
                autoFocus
              />

              <TouchableOpacity
                style={[styles.button, isLoading && styles.buttonDisabled]}
                onPress={handleVerifyEmail}
                disabled={isLoading || !isLoaded || !verificationCode}
              >
                <Text style={styles.buttonText}>
                  {isLoading ? 'Verifying...' : 'Verify Code'}
                </Text>
              </TouchableOpacity>

              <TouchableOpacity
                style={styles.linkButton}
                onPress={() => {
                  setNeedsEmailVerification(false);
                  setVerificationCode('');
                }}
                disabled={isLoading}
              >
                <Text style={styles.linkText}>Back to Sign Up</Text>
              </TouchableOpacity>
            </>
          )}
        </View>
      </View>
    </KeyboardAvoidingView>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: colors.background.primary,
  },
  content: {
    flex: 1,
    justifyContent: 'center',
    padding: 24,
  },
  title: {
    fontSize: 32,
    fontWeight: 'bold',
    color: colors.text.primary,
    marginBottom: 8,
    textAlign: 'center',
  },
  subtitle: {
    fontSize: 16,
    color: colors.text.secondary,
    marginBottom: 32,
    textAlign: 'center',
  },
  form: {
    gap: 16,
  },
  input: {
    backgroundColor: colors.background.secondary,
    borderRadius: 8,
    padding: 16,
    fontSize: 16,
    color: colors.text.primary,
    borderWidth: 1,
    borderColor: colors.border.light,
  },
  button: {
    backgroundColor: colors.accent.coral,
    borderRadius: 8,
    padding: 16,
    alignItems: 'center',
    marginTop: 8,
  },
  buttonDisabled: {
    opacity: 0.6,
  },
  buttonText: {
    color: '#FFFFFF',
    fontSize: 16,
    fontWeight: '600',
  },
  verificationText: {
    fontSize: 14,
    color: colors.text.secondary,
    textAlign: 'center',
    marginBottom: 8,
  },
  linkButton: {
    padding: 12,
    alignItems: 'center',
  },
  linkText: {
    color: colors.accent.coral,
    fontSize: 14,
    fontWeight: '500',
  },
});

