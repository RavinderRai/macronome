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
    ...typography.textStyles.h1,
    color: colors.text.primary,
    marginBottom: spacing.md,
  },
  subtitle: {
    ...typography.textStyles.body,
    color: colors.text.secondary,
  },
});

