/**
 * Pantry Item List Component
 * Renders list of pantry items with sections and empty state
 */

import React from 'react';
import { View, Text, FlatList, StyleSheet } from 'react-native';
import { colors, spacing } from '../../theme';
import type { PantryItem as PantryItemType } from '../../types/pantry';
import PantryItem from './PantryItem';
import EmptyState from '../common/EmptyState';

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
			<EmptyState
				icon="🧺"
				title="No pantry items"
				message="Tap the camera button to scan your fridge or pantry"
			/>
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
});