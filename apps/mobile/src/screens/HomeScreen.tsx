/**
 * HomeScreen
 * Main chat interface screen
 */

import React from 'react';
import { View, Text, StyleSheet } from 'react-native';
import { colors } from '../theme';
import { typography } from '../theme';
import { spacing } from '../theme';

export default function HomeScreen() {
  return (
    <View style={styles.container}>
      <Text style={styles.title}>Macronome</Text>
      <Text style={styles.subtitle}>Eat in Rhythm, Not in Restriction</Text>
      <Text style={styles.subtitle}>Home Screen - Coming Soon</Text>
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: colors.background.primary,
    alignItems: 'center',
    justifyContent: 'center',
    padding: spacing.lg,
  },
  title: {
    fontSize: 36,
    fontWeight: '700',
    color: '#FFFFFF',
    marginBottom: spacing.md,
    textAlign: 'center',
  },
  subtitle: {
    fontSize: 16,
    fontWeight: '400',
    color: '#DEE2E6',
    textAlign: 'center',
    marginTop: spacing.sm,
  },
});

