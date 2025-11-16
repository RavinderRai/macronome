/**
 * Sign In Screen
 * Clerk-powered sign in with email
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
import { useSignIn } from '@clerk/clerk-expo';
import { colors } from '../../theme/colors';
import { ENV } from '../../utils/env';

export default function SignInScreen() {
  const { signIn, setActive, isLoaded } = useSignIn();
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [isLoading, setIsLoading] = useState(false);

  // Debug: Log configuration on mount
  useEffect(() => {
    console.log('=== SignInScreen Configuration ===');
    console.log('Clerk isLoaded:', isLoaded);
    console.log('API Base URL:', ENV.apiBaseUrl);
    console.log('Clerk Key configured:', !!ENV.clerkPublishableKey);
    console.log('==================================');
  }, [isLoaded]);

  const handleSignIn = async () => {
    console.log('handleSignIn called');
    
    if (!isLoaded) {
      console.log('Clerk not loaded yet');
      return;
    }

    if (!email || !password) {
      Alert.alert('Error', 'Please enter both email and password');
      return;
    }

    setIsLoading(true);

    try {
      console.log('Creating sign-in attempt...');
      const result = await signIn.create({
        identifier: email,
        password,
      });

      console.log('Sign-in result status:', result.status);
      console.log('Created session ID:', result.createdSessionId);

      // Activate session if we have a session ID (more reliable than checking status)
      if (result.createdSessionId) {
        console.log('Setting active session...');
        await setActive({ session: result.createdSessionId });
        console.log('Session activated successfully');
        // Navigation will be handled by auth state change
      } else if (result.status === 'complete') {
        // Fallback: if status is complete but no session ID, try to get it from signIn object
        console.log('Status is complete, attempting to activate...');
        if (signIn.createdSessionId) {
          await setActive({ session: signIn.createdSessionId });
          console.log('Session activated successfully');
        } else {
          console.log('No session ID available despite complete status');
          Alert.alert('Error', 'Sign in incomplete. Please try again.');
        }
      } else if (result.status === 'needs_second_factor') {
        // 2FA is required but user has it disabled - this is a Clerk config issue
        console.error('needs_second_factor but user has 2FA disabled');
        console.log('Available second factors:', signIn.supportedSecondFactors);
        
        Alert.alert(
          'Sign In Issue',
          'Clerk is requiring 2FA even though it\'s disabled for your account.\n\n' +
          'Please check Clerk Dashboard:\n\n' +
          '1. Session management → Sessions → Look for "Session verification level"\n' +
          '2. User & authentication → Multi-factor → Require MFA = "Optional"\n' +
          '3. Try deleting this user and signing up again\n\n' +
          'This is a Clerk configuration issue, not a code issue.',
          [{ text: 'OK' }]
        );
      } else {
        console.log('Sign-in incomplete, status:', result.status);
        Alert.alert('Error', `Sign in incomplete. Status: ${result.status}. Please try again.`);
      }
    } catch (error: any) {
      console.error('Sign in error:', error);
      console.error('Error details:', JSON.stringify(error.errors || error.message));
      Alert.alert('Sign In Failed', error.errors?.[0]?.message || error.message || 'An error occurred');
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
        <Text style={styles.title}>Welcome to Macronome</Text>
        <Text style={styles.subtitle}>Sign in to get started</Text>

        <View style={styles.form}>
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
            placeholder="Password"
            placeholderTextColor={colors.text.muted}
            value={password}
            onChangeText={setPassword}
            secureTextEntry
            autoCapitalize="none"
            editable={!isLoading}
          />

          <TouchableOpacity
            style={[styles.button, isLoading && styles.buttonDisabled]}
            onPress={handleSignIn}
            disabled={isLoading || !isLoaded}
          >
            <Text style={styles.buttonText}>
              {isLoading ? 'Signing in...' : 'Sign In'}
            </Text>
          </TouchableOpacity>
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
});

