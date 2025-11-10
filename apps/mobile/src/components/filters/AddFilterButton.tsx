/**
 * Add Filter Button Component
 * Button for adding items to filter (used for excluded ingredients)
 */

import React from 'react';
import { TouchableOpacity, Text, StyleSheet } from 'react-native';
import { colors } from '../../theme';
import { spacing } from '../../theme';

interface AddFilterButtonProps {
	label: string;
	onPress: () => void;
	disabled?: boolean;
}

export default function AddFilterButton({ 
	label, 
	onPress,
	disabled = false 
}: AddFilterButtonProps) {
	return (
		<TouchableOpacity 
			style={[
				styles.container,
				disabled && styles.disabled
			]}
			onPress={onPress}
			disabled={disabled}
			activeOpacity={0.7}
		>
			<Text style={[
				styles.text,
				disabled && styles.disabledText
			]}>
				+ {label}
			</Text>
		</TouchableOpacity>
	);
}

const styles = StyleSheet.create({
	container: {
		paddingVertical: spacing.sm,
		paddingHorizontal: spacing.md,
		borderRadius: 20,
		borderWidth: 1,
		borderColor: colors.border.light,
		marginRight: spacing.sm,
		marginBottom: spacing.sm,
	},
	text: {
		fontSize: 14,
		fontWeight: '500',
		lineHeight: 20,
		color: colors.text.secondary,
	},
	disabled: {
		opacity: 0.5,
		borderColor: colors.border.dark,
	},
	disabledText: {
		color: colors.text.muted,
	},
});

