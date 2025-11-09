import React from 'react';
import { View, Text, TouchableOpacity, StyleSheet } from 'react-native';
import { colors } from '../../theme';
import { typography } from '../../theme';
import { spacing } from '../../theme';
import { usePantryStore } from '../../store';
import { useUIStore } from '../../store';

interface HeaderProps {
    title?: string;
    onPantryPress?: () => void;
    onSettingsPress?: () => void;
}

export default function Header({
    title = 'Macronome',
    onPantryPress,
    onSettingsPress,
}: HeaderProps) {
    const pantryItems = usePantryStore((state) => state.items);
    const drawerOpen = useUIStore((state) => state.drawerOpen);
    const setDrawerOpen = useUIStore((state) => state.setDrawerOpen);

    const pantryCount = pantryItems.filter((item) => item.confirmed).length;

    const handlePantryPress = () => {
        if (onPantryPress) {
            onPantryPress();
        } else {
            setDrawerOpen(!drawerOpen);
        }
    };

    return (
        <View style={styles.container}>
            <TouchableOpacity 
                style={styles.pantryButton} 
                onPress={handlePantryPress}
                activeOpacity={0.7}
            >
                <Text style={styles.pantryIcon}>🧺</Text>
                {pantryCount > 0 && (
                    <View style={styles.badge}>
                        <Text style={styles.badgeText}>{pantryCount}</Text>
                    </View>
                )}
            </TouchableOpacity>

            <Text style={styles.title}>{title}</Text>

            <TouchableOpacity 
                style={styles.settingsButton} 
                onPress={onSettingsPress}
                activeOpacity={0.7}
            >
                <Text style={styles.settingsIcon}>⚙️</Text>
            </TouchableOpacity>
        </View>
    );
}

const styles = StyleSheet.create({
	container: {
		flexDirection: 'row',
		alignItems: 'center',
		justifyContent: 'space-between',
		paddingHorizontal: spacing.md,
		paddingVertical: spacing.md,
		backgroundColor: colors.background.primary,
		borderBottomWidth: 1,
		borderBottomColor: colors.border.light,
	},
	pantryButton: {
		position: 'relative',
		padding: spacing.sm,
	},
	pantryIcon: {
		fontSize: 24,
	},
	badge: {
		position: 'absolute',
		top: 0,
		right: 0,
		backgroundColor: colors.accent.coral,
		borderRadius: 10,
		minWidth: 20,
		height: 20,
		justifyContent: 'center',
		alignItems: 'center',
		paddingHorizontal: 4,
	},
	badgeText: {
		color: colors.text.primary,
		fontSize: 12,
		fontWeight: '600',
	},
	title: {
		...typography.textStyles.h2,
		color: colors.text.primary,
		flex: 1,
		textAlign: 'center',
	},
	settingsButton: {
		padding: spacing.sm,
	},
	settingsIcon: {
		fontSize: 24,
	},
});