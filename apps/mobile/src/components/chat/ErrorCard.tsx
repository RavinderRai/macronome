import React from 'react';
import { View, Text, StyleSheet } from 'react-native';
import { colors, spacing } from '../../theme';

interface ErrorCardProps {
  data: {
    error_message: string;
    suggestions?: string[];
  };
}

export default function ErrorCard({ data }: ErrorCardProps) {
  const { error_message, suggestions } = data;

  return (
    <View style={styles.container}>
      {/* Error icon and message */}
      <View style={styles.header}>
        <Text style={styles.errorIcon}>⚠️</Text>
        <Text style={styles.errorTitle}>Couldn't find a perfect match</Text>
      </View>

      {/* Error message */}
      <Text style={styles.errorMessage}>{error_message}</Text>

      {/* Suggestions (if available) */}
      {suggestions && suggestions.length > 0 && (
        <View style={styles.suggestionsSection}>
          <Text style={styles.suggestionsTitle}>Try these suggestions:</Text>
          {suggestions.map((suggestion, index) => (
            <View key={index} style={styles.suggestionItem}>
              <Text style={styles.bulletPoint}>•</Text>
              <Text style={styles.suggestionText}>{suggestion}</Text>
            </View>
          ))}
        </View>
      )}
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    backgroundColor: colors.primary.light,
    borderRadius: 12,
    padding: spacing.md,
    marginBottom: spacing.md,
    borderWidth: 1,
    borderColor: colors.semantic.warning,
  },
  header: {
    flexDirection: 'row',
    alignItems: 'center',
    marginBottom: spacing.sm,
  },
  errorIcon: {
    fontSize: 24,
    marginRight: spacing.sm,
  },
  errorTitle: {
    fontSize: 16,
    fontWeight: '600',
    color: colors.text.primary,
    flex: 1,
  },
  errorMessage: {
    fontSize: 14,
    lineHeight: 20,
    color: colors.text.secondary,
    marginBottom: spacing.md,
  },
  suggestionsSection: {
    backgroundColor: colors.primary.dark,
    borderRadius: 8,
    padding: spacing.sm,
    borderLeftWidth: 3,
    borderLeftColor: colors.accent.amber,
  },
  suggestionsTitle: {
    fontSize: 14,
    fontWeight: '600',
    color: colors.text.primary,
    marginBottom: spacing.sm,
  },
  suggestionItem: {
    flexDirection: 'row',
    marginBottom: spacing.xs,
    paddingLeft: spacing.xs,
  },
  bulletPoint: {
    fontSize: 14,
    color: colors.accent.amber,
    marginRight: spacing.xs,
    marginTop: 2,
  },
  suggestionText: {
    flex: 1,
    fontSize: 14,
    lineHeight: 20,
    color: colors.text.secondary,
  },
});

