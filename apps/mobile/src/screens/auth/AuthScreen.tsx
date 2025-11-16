/**
 * Auth Screen
 * Container that switches between Sign In and Sign Up
 */
import React, { useState } from 'react';
import { View, Text, TouchableOpacity, StyleSheet } from 'react-native';
import SignInScreen from './SignInScreen';
import SignUpScreen from './SignUpScreen';
import { colors } from '../../theme/colors';

export default function AuthScreen() {
  const [isSignUp, setIsSignUp] = useState(false);

  return (
    <View style={styles.container}>
      {isSignUp ? <SignUpScreen /> : <SignInScreen />}
      
      <View style={styles.switchContainer}>
        <Text style={styles.switchText}>
          {isSignUp ? "Already have an account? " : "Don't have an account? "}
        </Text>
        <TouchableOpacity onPress={() => setIsSignUp(!isSignUp)}>
          <Text style={styles.switchLink}>
            {isSignUp ? 'Sign In' : 'Sign Up'}
          </Text>
        </TouchableOpacity>
      </View>
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
  },
  switchContainer: {
    flexDirection: 'row',
    justifyContent: 'center',
    padding: 24,
    backgroundColor: colors.background.primary,
  },
  switchText: {
    color: colors.text.secondary,
    fontSize: 14,
  },
  switchLink: {
    color: colors.accent.coral,
    fontSize: 14,
    fontWeight: '600',
  },
});

