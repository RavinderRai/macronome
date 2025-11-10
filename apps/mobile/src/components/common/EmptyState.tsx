import React from 'react';
import { View, Text, StyleSheet } from 'react-native';
import { colors } from '../../theme';
import { spacing } from '../../theme';

interface EmptyStateProps {
    icon?: string;
    title: string;
    message?: string;
}

export default function EmptyState({
	icon = '📭',
	title,
	message,
}: EmptyStateProps) {
	return (
		<View style={styles.container}>
			<Text style={styles.icon}>{icon}</Text>
			<Text style={styles.title}>{title}</Text>
			{message && (
				<Text style={styles.message}>{message}</Text>
			)}
		</View>
	);
}

const styles = StyleSheet.create({
	container: {
		flex: 1,
		alignItems: 'center',
		justifyContent: 'center',
		padding: spacing.xl,
	},
	icon: {
		fontSize: 64,
		marginBottom: spacing.md,
	},
	title: {
		fontSize: 20,
		fontWeight: '600',
		lineHeight: 28,
		color: colors.text.primary,
		marginBottom: spacing.sm,
		textAlign: 'center',
	},
	message: {
		fontSize: 16,
		lineHeight: 24,
		color: colors.text.secondary,
		textAlign: 'center',
		maxWidth: 300,
	},
});