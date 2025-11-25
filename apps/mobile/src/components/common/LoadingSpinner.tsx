import React from 'react';
import { View, ActivityIndicator, Text, StyleSheet } from 'react-native';
import { colors } from '../../theme';
import { spacing } from '../../theme';

interface LoadingSpinnerProps {
    size?: 'small' | 'large';
    color?: string;
    message?: string;
    fullScreen?: boolean;
}

export default function LoadingSpinner({
    size = 'large',
    color = colors.accent.coral, // Warm orange spinner
    message,
    fullScreen = false,
}: LoadingSpinnerProps) {
	const containerStyle = fullScreen ? styles.fullScreen : styles.container;

	return (
		<View style={containerStyle}>
			<ActivityIndicator size={size} color={color} />
			{message && (
				<Text style={styles.message}>{message}</Text>
			)}
		</View>
	);
}

const styles = StyleSheet.create({
    container: {
        padding: spacing.lg,
        alignItems: 'center',
        justifyContent: 'center',
    },
    fullScreen: {
        flex: 1,
        alignItems: 'center',
        justifyContent: 'center',
        backgroundColor: colors.background.primary,
    },
    message: {
        fontSize: 16,
        lineHeight: 24,
        color: colors.text.primary, // White text for better contrast on dark backgrounds
        marginTop: spacing.md,
        textAlign: 'center',
    },
});