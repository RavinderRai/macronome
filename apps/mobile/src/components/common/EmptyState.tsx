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
	// Split message by newlines to render bullet points with proper spacing
	const messageLines = message?.split('\n').filter(line => line.trim()) || [];
	
	return (
		<View style={styles.container}>
			<Text style={styles.icon}>{icon}</Text>
			<Text style={styles.title}>{title}</Text>
			{messageLines.length > 0 && (
				<View style={styles.messageContainer}>
					{messageLines.map((line, index) => (
						<Text 
							key={index} 
							style={[
								styles.message,
								index === messageLines.length - 1 && styles.messageLast
							]}
						>
							{line}
						</Text>
					))}
				</View>
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
	messageContainer: {
		alignItems: 'center',
		maxWidth: 320,
	},
	message: {
		fontSize: 15,
		lineHeight: 24,
		color: colors.text.secondary,
		textAlign: 'left',
		marginBottom: spacing.xs,
		width: '100%',
	},
	messageLast: {
		marginBottom: 0,
	},
});