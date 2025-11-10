/**
 * Pantry Item Component
 * Individual row for a pantry item with confirm/delete actions
 */

import React from 'react';
import { View, Text, TouchableOpacity, StyleSheet } from 'react-native';
import { colors, spacing } from '../../theme';
import type { PantryItem as PantryItemType } from '../../types/pantry';

interface PantryItemProps {
    item: PantryItemType;
    onConfirm: (id: string) => void;
    onUnconfirm: (id: string) => void;
    onRemove: (id: string) => void;
}

export default function PantryItem({
    item,
    onConfirm,
    onUnconfirm,
    onRemove,
}: PantryItemProps) {
    const handleToggleConfirm = () => {
        if (item.confirmed) {
            onUnconfirm(item.id);
        } else {
            onConfirm(item.id);
        }
    };

	return (
		<View style={styles.container}>
			{/* Checkbox for confirming item */}
			<TouchableOpacity
				style={styles.checkbox}
				onPress={handleToggleConfirm}
				activeOpacity={0.7}
			>
				<Text style={styles.checkboxIcon}>
					{item.confirmed ? '✓' : '○'}
				</Text>
			</TouchableOpacity>

			{/* Item details */}
			<View style={styles.content}>
				<Text
					style={[
						styles.name,
						item.confirmed && styles.nameConfirmed,
					]}
				>
					{item.name}
				</Text>

				{/* Show confidence and category if available */}
				<View style={styles.metaRow}>
					{item.confidence !== undefined && (
						<Text style={styles.metaText}>
							{Math.round(item.confidence * 100)}% confident
						</Text>
					)}
					{item.category && (
						<Text style={styles.metaText}>• {item.category}</Text>
					)}
				</View>
			</View>

			{/* Delete button */}
			<TouchableOpacity
				style={styles.deleteButton}
				onPress={() => onRemove(item.id)}
				activeOpacity={0.7}
			>
				<Text style={styles.deleteIcon}>✕</Text>
			</TouchableOpacity>
		</View>
	);
}

const styles = StyleSheet.create({
	container: {
		flexDirection: 'row',
		alignItems: 'center',
		paddingVertical: spacing.md,
		paddingHorizontal: spacing.md,
		backgroundColor: colors.background.secondary,
		borderRadius: 8,
		marginBottom: spacing.sm,
	},
	checkbox: {
		width: 28,
		height: 28,
		borderRadius: 14,
		borderWidth: 2,
		borderColor: colors.accent.coral,
		alignItems: 'center',
		justifyContent: 'center',
		marginRight: spacing.md,
	},
	checkboxIcon: {
		fontSize: 16,
		color: colors.accent.coral,
	},
	content: {
		flex: 1,
	},
	name: {
		fontSize: 16,
		lineHeight: 20,
		fontWeight: '600',
		color: colors.text.primary,
		marginBottom: spacing.xs,
	},
	nameConfirmed: {
		opacity: 0.7,
	},
	metaRow: {
		flexDirection: 'row',
		gap: spacing.sm,
	},
	metaText: {
		fontSize: 12,
		lineHeight: 16,
		color: colors.text.secondary,
	},
	deleteButton: {
		width: 32,
		height: 32,
		alignItems: 'center',
		justifyContent: 'center',
		marginLeft: spacing.sm,
	},
	deleteIcon: {
		fontSize: 20,
		color: colors.text.muted,
	},
});