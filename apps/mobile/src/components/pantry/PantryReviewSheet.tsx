/**
 * Pantry Review Sheet Component
 * Bottom sheet for reviewing and confirming scanned pantry items
 */

import React, { useEffect } from 'react';
import { 
	View, 
	Text, 
	StyleSheet, 
	TouchableOpacity, 
	FlatList, 
	Modal,
	Animated,
	Dimensions
} from 'react-native';
import { colors, spacing } from '../../theme';

interface PendingItem {
	name: string;
	category?: string;
	confidence?: number;
	confirmed: boolean;
	selected: boolean; // For local selection before adding
}

interface PantryReviewSheetProps {
	items: Omit<PendingItem, 'selected'>[];
	visible: boolean;
	onClose: () => void;
	onConfirm: (confirmedItems: Omit<PendingItem, 'selected'>[]) => void;
}

const SCREEN_HEIGHT = Dimensions.get('window').height;

export default function PantryReviewSheet({
	items,
	visible,
	onClose,
	onConfirm,
}: PantryReviewSheetProps) {
	const [selectedItems, setSelectedItems] = React.useState<PendingItem[]>([]);
	const slideAnim = React.useRef(new Animated.Value(SCREEN_HEIGHT)).current;

	// Initialize selected items when items change
	useEffect(() => {
		if (items.length > 0) {
			setSelectedItems(
				items.map((item) => ({
					...item,
					selected: true, // All items selected by default
				}))
			);
		}
	}, [items]);

	// Animate sheet when visibility changes
	useEffect(() => {
		if (visible) {
			console.log('📱 Showing modal sheet...');
			Animated.spring(slideAnim, {
				toValue: 0,
				useNativeDriver: true,
				damping: 20,
			}).start();
		} else {
			Animated.timing(slideAnim, {
				toValue: SCREEN_HEIGHT,
				duration: 250,
				useNativeDriver: true,
			}).start();
		}
	}, [visible]);

	const toggleItemSelection = (index: number) => {
		setSelectedItems((prev) =>
			prev.map((item, i) =>
				i === index ? { ...item, selected: !item.selected } : item
			)
		);
	};

	const handleConfirm = () => {
		const confirmedItems = selectedItems
			.filter((item) => item.selected)
			.map(({ selected, ...item }) => item);
		
		onConfirm(confirmedItems);
		onClose();
	};

	const handleCancel = () => {
		onClose();
	};

	const selectedCount = selectedItems.filter((item) => item.selected).length;

	if (!visible && items.length === 0) return null;

	console.log('✅ Review modal rendering. Visible:', visible, 'Items:', items.length);

	return (
		<Modal
			visible={visible}
			transparent={true}
			animationType="none"
			onRequestClose={onClose}
		>
			<View style={styles.overlay}>
				{/* Backdrop */}
				<TouchableOpacity 
					style={styles.backdrop} 
					activeOpacity={1} 
					onPress={onClose}
				/>

				{/* Sheet */}
				<Animated.View 
					style={[
						styles.sheet,
						{
							transform: [{ translateY: slideAnim }],
						},
					]}
				>
					{/* Handle */}
					<View style={styles.handle} />
					
					<View style={styles.container}>
				{/* Header */}
				<View style={styles.header}>
					<Text style={styles.headerTitle}>Review Scanned Items</Text>
					<Text style={styles.headerSubtitle}>
						{selectedCount} of {items.length} selected
					</Text>
				</View>

				{/* Items list */}
				<FlatList
					data={selectedItems}
					keyExtractor={(item, index) => `${item.name}-${index}`}
					renderItem={({ item, index }) => (
						<TouchableOpacity
							style={[
								styles.itemContainer,
								item.selected && styles.itemSelected,
							]}
							onPress={() => toggleItemSelection(index)}
							activeOpacity={0.7}
						>
							{/* Checkbox */}
							<View
								style={[
									styles.checkbox,
									item.selected && styles.checkboxSelected,
								]}
							>
								{item.selected && (
									<Text style={styles.checkmark}>✓</Text>
								)}
							</View>

							{/* Item details */}
							<View style={styles.itemContent}>
								<Text style={styles.itemName}>{item.name}</Text>
								<View style={styles.itemMeta}>
									{item.category && (
										<Text style={styles.itemMetaText}>
											{item.category}
										</Text>
									)}
									{item.confidence !== undefined && (
										<Text style={styles.itemMetaText}>
											• {Math.round(item.confidence * 100)}% confident
										</Text>
									)}
								</View>
							</View>
						</TouchableOpacity>
					)}
					contentContainerStyle={styles.listContent}
					showsVerticalScrollIndicator={true}
				/>

				{/* Actions */}
				<View style={styles.actions}>
					<TouchableOpacity
						style={styles.cancelButton}
						onPress={handleCancel}
						activeOpacity={0.7}
					>
						<Text style={styles.cancelButtonText}>Cancel</Text>
					</TouchableOpacity>

					<TouchableOpacity
						style={[
							styles.confirmButton,
							selectedCount === 0 && styles.confirmButtonDisabled,
						]}
						onPress={handleConfirm}
						disabled={selectedCount === 0}
						activeOpacity={0.7}
					>
						<Text style={styles.confirmButtonText}>
							Add {selectedCount} {selectedCount === 1 ? 'Item' : 'Items'}
						</Text>
					</TouchableOpacity>
				</View>
			</View>
				</Animated.View>
			</View>
		</Modal>
	);
}

const styles = StyleSheet.create({
	overlay: {
		flex: 1,
		justifyContent: 'flex-end',
	},
	backdrop: {
		...StyleSheet.absoluteFillObject,
		backgroundColor: 'rgba(0, 0, 0, 0.5)',
	},
	sheet: {
		backgroundColor: colors.background.primary,
		borderTopLeftRadius: 20,
		borderTopRightRadius: 20,
		maxHeight: SCREEN_HEIGHT * 0.85,
		shadowColor: '#000',
		shadowOffset: { width: 0, height: -3 },
		shadowOpacity: 0.3,
		shadowRadius: 8,
		elevation: 16,
	},
	handle: {
		width: 40,
		height: 4,
		backgroundColor: colors.border.light,
		borderRadius: 2,
		alignSelf: 'center',
		marginTop: spacing.sm,
		marginBottom: spacing.sm,
	},
	container: {
		paddingHorizontal: spacing.md,
		paddingBottom: spacing.md,
	},
	header: {
		paddingVertical: spacing.md,
		borderBottomWidth: 1,
		borderBottomColor: colors.border.light,
		marginBottom: spacing.md,
	},
	headerTitle: {
		fontSize: 20,
		fontWeight: '700',
		lineHeight: 28,
		color: colors.text.primary,
		marginBottom: spacing.xs,
	},
	headerSubtitle: {
		fontSize: 14,
		lineHeight: 20,
		color: colors.text.secondary,
	},
	listContent: {
		paddingBottom: spacing.md,
	},
	itemContainer: {
		flexDirection: 'row',
		alignItems: 'center',
		paddingVertical: spacing.md,
		paddingHorizontal: spacing.md,
		backgroundColor: colors.background.secondary,
		borderRadius: 8,
		marginBottom: spacing.sm,
		borderWidth: 2,
		borderColor: 'transparent',
	},
	itemSelected: {
		borderColor: colors.accent.coral,
		backgroundColor: colors.primary.light,
	},
	checkbox: {
		width: 24,
		height: 24,
		borderRadius: 12,
		borderWidth: 2,
		borderColor: colors.border.light,
		alignItems: 'center',
		justifyContent: 'center',
		marginRight: spacing.md,
	},
	checkboxSelected: {
		backgroundColor: colors.accent.coral,
		borderColor: colors.accent.coral,
	},
	checkmark: {
		fontSize: 14,
		color: colors.text.primary,
		fontWeight: '700',
	},
	itemContent: {
		flex: 1,
	},
	itemName: {
		fontSize: 16,
		fontWeight: '600',
		lineHeight: 22,
		color: colors.text.primary,
		marginBottom: spacing.xs,
	},
	itemMeta: {
		flexDirection: 'row',
		gap: spacing.sm,
	},
	itemMetaText: {
		fontSize: 12,
		lineHeight: 16,
		color: colors.text.secondary,
	},
	actions: {
		flexDirection: 'row',
		gap: spacing.md,
		paddingVertical: spacing.md,
		borderTopWidth: 1,
		borderTopColor: colors.border.light,
	},
	cancelButton: {
		flex: 1,
		paddingVertical: spacing.md,
		borderRadius: 8,
		borderWidth: 1,
		borderColor: colors.border.light,
		alignItems: 'center',
		justifyContent: 'center',
	},
	cancelButtonText: {
		fontSize: 16,
		fontWeight: '600',
		lineHeight: 24,
		color: colors.text.secondary,
	},
	confirmButton: {
		flex: 2,
		paddingVertical: spacing.md,
		borderRadius: 8,
		backgroundColor: colors.accent.coral,
		alignItems: 'center',
		justifyContent: 'center',
	},
	confirmButtonDisabled: {
		opacity: 0.5,
	},
	confirmButtonText: {
		fontSize: 16,
		fontWeight: '600',
		lineHeight: 24,
		color: colors.text.primary,
	},
});

