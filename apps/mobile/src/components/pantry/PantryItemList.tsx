/**
 * Pantry Item List Component
 * Renders list of pantry items with sections and empty state
 */

import React from 'react';
import { View, Text, FlatList, StyleSheet } from 'react-native';
import { colors, spacing } from '../../theme';
import type { PantryItem as PantryItemType } from '../../types/pantry';
import PantryItem from './PantryItem';

interface PantryItemListProps {
	items: PantryItemType[];
	onConfirm: (id: string) => void;
	onUnconfirm: (id: string) => void;
	onRemove: (id: string) => void;
}

export default function PantryItemList({
	items,
	onConfirm,
	onUnconfirm,
	onRemove,
}: PantryItemListProps) {
	// Separate items into confirmed and unconfirmed
	const unconfirmedItems = items.filter((item) => !item.confirmed);
	const confirmedItems = items.filter((item) => item.confirmed);

	// Show empty state if no items
	if (items.length === 0) {
		return (
			<View style={styles.emptyContainer}>
				<Text style={styles.emptyIcon}>🧺</Text>
				<Text style={styles.emptyTitle}>No pantry items</Text>
				<View style={styles.emptyMessageContainer}>
					<Text style={styles.emptyMessage} numberOfLines={1}>Tap the camera button</Text>
					<Text style={styles.emptyMessage} numberOfLines={1}>to scan your fridge or pantry</Text>
					<Text style={styles.emptyMessage} numberOfLines={1}>Then pick which items to use</Text>
					<Text style={styles.emptyMessage} numberOfLines={1}>and we'll include them in your meal</Text>
				</View>
			</View>
		);
	}

	return (
		<FlatList
			data={items}
			keyExtractor={(item) => item.id}
			renderItem={({ item }) => (
				<PantryItem
					item={item}
					onConfirm={onConfirm}
					onUnconfirm={onUnconfirm}
					onRemove={onRemove}
				/>
			)}
			ListHeaderComponent={
				<>
					{/* Unconfirmed section header */}
					{unconfirmedItems.length > 0 && (
						<View style={styles.sectionHeader}>
							<Text style={styles.sectionTitle}>
								Detected Items ({unconfirmedItems.length})
							</Text>
							<Text style={styles.sectionSubtitle}>
								Review and confirm
							</Text>
						</View>
					)}
				</>
			}
			ItemSeparatorComponent={() => <View style={styles.separator} />}
			contentContainerStyle={styles.listContent}
			showsVerticalScrollIndicator={true}
		/>
	);
}

const styles = StyleSheet.create({
	listContent: {
		padding: spacing.md,
	},
	sectionHeader: {
		marginBottom: spacing.md,
	},
	sectionTitle: {
		fontSize: 16,
		lineHeight: 20,
		fontWeight: '700',
		color: colors.text.primary,
		marginBottom: spacing.xs,
	},
	sectionSubtitle: {
		fontSize: 14,
		lineHeight: 18,
		color: colors.text.secondary,
	},
	separator: {
		height: 0,
	},
	emptyContainer: {
		flex: 1,
		alignItems: 'center',
		justifyContent: 'center',
		padding: spacing.xl,
	},
	emptyIcon: {
		fontSize: 64,
		marginBottom: spacing.md,
	},
	emptyTitle: {
		fontSize: 20,
		fontWeight: '600',
		lineHeight: 28,
		color: colors.text.primary,
		marginBottom: spacing.sm,
		textAlign: 'center',
	},
	emptyMessageContainer: {
		alignItems: 'center',
		maxWidth: 240,
		width: '100%',
	},
	emptyMessage: {
		fontSize: 15,
		lineHeight: 24,
		color: colors.text.secondary,
		textAlign: 'center',
	},
});