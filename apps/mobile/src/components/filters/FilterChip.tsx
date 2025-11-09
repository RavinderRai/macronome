import React from 'react';
import { View, Text, TouchableOpacity, StyleSheet } from 'react-native';
import { colors } from '../../theme';
import { typography } from '../../theme';
import { spacing } from '../../theme';

interface FilterChipProps {
    label: string;
    onRemove?: () => void;
    variant?: 'default' | 'accent';
}

export default function FilterChip({
    label,
    onRemove,
    variant = 'default',
}: FilterChipProps) {
    const backgroundColor = variant === 'accent'
        ? colors.accent.coral
        : colors.primary.light;

    return (
        <View style={[styles.container, {backgroundColor}]}>
            {/* Label text */}
            <Text style={styles.label}>{label}</Text>

            {/* Remove button */}
            {onRemove && (
                <TouchableOpacity
                    onPress={onRemove}
                    style={styles.removeButton}
                    hitSlop={{ top: 10, bottom: 10, left: 10, right: 10 }}
                >
                    <Text style={styles.removeIcon}>✕</Text>
                </TouchableOpacity>
            )}
        </View>
    );
}

const styles = StyleSheet.create({
	container: {
		flexDirection: 'row',           // Horizontal layout
		alignItems: 'center',
		paddingVertical: spacing.sm,
		paddingHorizontal: spacing.md,
		borderRadius: 20,               // Rounded pill shape
		marginRight: spacing.sm,
		marginBottom: spacing.sm,
	},
	label: {
		...typography.textStyles.label,
		color: colors.text.primary,
	},
	removeButton: {
		marginLeft: spacing.sm,
		width: 20,
		height: 20,
		justifyContent: 'center',
		alignItems: 'center',
	},
	removeIcon: {
		fontSize: 20,
		color: colors.text.primary,
		fontWeight: '600',
	},
});