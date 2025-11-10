/**
 * Pantry Drawer Component
 * Left-side drawer for viewing and managing pantry items
 */

import React, { useRef, useEffect } from 'react';
import {
	View,
	Text,
	TouchableOpacity,
	StyleSheet,
	Modal,
	Animated,
	Dimensions,
	TouchableWithoutFeedback,
} from 'react-native';
import { colors, spacing } from '../../theme';
import { usePantryStore, useUIStore } from '../../store';
import PantryItemList from './PantryItemList';

const DRAWER_WIDTH = Dimensions.get('window').width * 0.85; // 85% of screen width

interface PantryDrawerProps {
    onCameraPress?: () => void;
}

export default function PantryDrawer({ onCameraPress }: PantryDrawerProps) {
	const items = usePantryStore((state) => state.items);
	const confirmItem = usePantryStore((state) => state.confirmItem);
	const unconfirmItem = usePantryStore((state) => state.unconfirmItem);
	const removeItem = usePantryStore((state) => state.removeItem);
	const clearItems = usePantryStore((state) => state.clearItems);

	const drawerOpen = useUIStore((state) => state.drawerOpen);
	const setDrawerOpen = useUIStore((state) => state.setDrawerOpen);

    // Animation value for drawer slide
    const slideAnim = useRef(new Animated.Value(0)).current;

    // Animate drawer when opened/closed
    useEffect(() => {
        Animated.timing(slideAnim, {
            toValue: drawerOpen ? 1 : 0,
            duration: 300,
            useNativeDriver: true,
        }).start();
    }, [drawerOpen, slideAnim]);

    // Calculate drawer transform
    const translateX = slideAnim.interpolate({
        inputRange: [0, 1],
        outputRange: [-DRAWER_WIDTH, 0],
    })

    const confirmedCount = items.filter((item) => item.confirmed).length;

    const handleClose = () => {
        setDrawerOpen(false);
    };

    const handleCameraPress = () => {
        handleClose();
        if (onCameraPress) {
            onCameraPress();
        }
    };

	return (
		<Modal
			visible={drawerOpen}
			transparent={true}
			animationType="none"
			onRequestClose={handleClose}
		>
			<View style={styles.overlay}>
				{/* Backdrop - tap to close */}
				<TouchableWithoutFeedback onPress={handleClose}>
					<Animated.View
						style={[
							styles.backdrop,
							{
								opacity: slideAnim,
							},
						]}
					/>
				</TouchableWithoutFeedback>

				{/* Drawer content */}
				<Animated.View
					style={[
						styles.drawer,
						{
							transform: [{ translateX }],
						},
					]}
				>
					{/* Header */}
					<View style={styles.header}>
						<View style={styles.headerTop}>
							<Text style={styles.headerTitle}>
								🧺 My Pantry
							</Text>
							<TouchableOpacity
								onPress={handleClose}
								activeOpacity={0.7}
								style={styles.closeButton}
							>
								<Text style={styles.closeIcon}>✕</Text>
							</TouchableOpacity>
						</View>

						{/* Item count */}
						<Text style={styles.itemCount}>
							{confirmedCount} {confirmedCount === 1 ? 'item' : 'items'} confirmed
						</Text>

						{/* Action buttons */}
						<View style={styles.actionButtons}>
							<TouchableOpacity
								style={styles.cameraButton}
								onPress={handleCameraPress}
								activeOpacity={0.7}
							>
								<Text style={styles.cameraIcon}>📷</Text>
								<Text style={styles.buttonText}>Scan Items</Text>
							</TouchableOpacity>

							{items.length > 0 && (
								<TouchableOpacity
									style={styles.clearButton}
									onPress={clearItems}
									activeOpacity={0.7}
								>
									<Text style={styles.clearButtonText}>
										Clear All
									</Text>
								</TouchableOpacity>
							)}
						</View>
					</View>

					{/* Item list */}
					<View style={styles.listContainer}>
						<PantryItemList
							items={items}
							onConfirm={confirmItem}
							onUnconfirm={unconfirmItem}
							onRemove={removeItem}
						/>
					</View>
				</Animated.View>
			</View>
		</Modal>
	);
}

const styles = StyleSheet.create({
	overlay: {
		flex: 1,
		flexDirection: 'row',
	},
	backdrop: {
		flex: 1,
		backgroundColor: 'rgba(0, 0, 0, 0.5)',
	},
	drawer: {
		position: 'absolute',
		left: 0,
		top: 0,
		bottom: 0,
		width: DRAWER_WIDTH,
		backgroundColor: colors.background.primary,
		shadowColor: '#000',
		shadowOffset: { width: 2, height: 0 },
		shadowOpacity: 0.3,
		shadowRadius: 8,
		elevation: 16,
	},
	header: {
		paddingTop: spacing.xl,
		paddingHorizontal: spacing.md,
		paddingBottom: spacing.md,
		borderBottomWidth: 1,
		borderBottomColor: colors.border.light,
	},
	headerTop: {
		flexDirection: 'row',
		alignItems: 'center',
		justifyContent: 'space-between',
		marginBottom: spacing.sm,
	},
	headerTitle: {
		fontSize: 24,
		lineHeight: 28,
		fontWeight: '700',
		color: colors.text.primary,
	},
	closeButton: {
		width: 32,
		height: 32,
		alignItems: 'center',
		justifyContent: 'center',
	},
	closeIcon: {
		fontSize: 24,
		color: colors.text.secondary,
	},
	itemCount: {
		fontSize: 14,
		lineHeight: 18,
		color: colors.text.secondary,
		marginBottom: spacing.md,
	},
	actionButtons: {
		flexDirection: 'row',
		gap: spacing.sm,
	},
	cameraButton: {
		flex: 1,
		flexDirection: 'row',
		alignItems: 'center',
		justifyContent: 'center',
		paddingVertical: spacing.md,
		paddingHorizontal: spacing.md,
		backgroundColor: colors.accent.coral,
		borderRadius: 8,
		gap: spacing.sm,
	},
	cameraIcon: {
		fontSize: 20,
	},
	buttonText: {
		fontSize: 16,
		lineHeight: 20,
		fontWeight: '600',
		color: colors.text.primary,
	},
	clearButton: {
		paddingVertical: spacing.md,
		paddingHorizontal: spacing.md,
		borderWidth: 1,
		borderColor: colors.border.light,
		borderRadius: 8,
	},
	clearButtonText: {
		fontSize: 16,
		lineHeight: 20,
		fontWeight: '600',
		color: colors.text.secondary,
	},
	listContainer: {
		flex: 1,
	},
});