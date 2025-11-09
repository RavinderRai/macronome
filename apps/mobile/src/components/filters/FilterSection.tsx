/**
 * Filter Section Component
 * Collapsible section with always-visible preset filter controls
 * App handles preset filters only, chat will handle more complex filter requests
 */

import React from 'react';
import { View, Text, TouchableOpacity, StyleSheet, TextInput, Alert } from 'react-native';
import { colors } from '../../theme';
import { typography } from '../../theme';
import { spacing } from '../../theme';
import { useFilterStore } from '../../store';
import { useUIStore } from '../../store';
import FilterChip from './FilterChip';

interface FilterSectionProps {
	// Optional callbacks for opening modals (can be added later)
	onEditCalories?: () => void;
	onEditMacros?: () => void;
	onEditDiet?: () => void;
}

export default function FilterSection({
	onEditCalories,
	onEditMacros,
	onEditDiet,
}: FilterSectionProps) {
	const [newIngredient, setNewIngredient] = React.useState('');

	// Get state from Zustand stores
	const constraints = useFilterStore((state) => state.constraints);
	const setCalories = useFilterStore((state) => state.setCalories);
	const setMacros = useFilterStore((state) => state.setMacros);
	const setDiet = useFilterStore((state) => state.setDiet);
	const addExcludedIngredient = useFilterStore((state) => state.addExcludedIngredient);
	const removeExcludedIngredient = useFilterStore((state) => state.removeExcludedIngredient);
	
	const filtersCollapsed = useUIStore((state) => state.filtersCollapsed);
	const toggleFilters = useUIStore((state) => state.toggleFilters);

	// Count active filters
	const activeFilterCount = [
		constraints.calories !== undefined,
		constraints.macros !== undefined,
		constraints.diet !== undefined,
		constraints.excludedIngredients.length > 0,
		constraints.prepTime !== undefined,
	].filter(Boolean).length;

	// Format display labels
	const getCaloriesLabel = () => {
		return constraints.calories ? `${constraints.calories} kcal or less` : null;
	};

	const getMacrosLabel = () => {
		if (!constraints.macros) return null;
		const parts = [];
		if (constraints.macros.carbs) parts.push(`Carbs: ${constraints.macros.carbs}`);
		if (constraints.macros.protein) parts.push(`Protein: ${constraints.macros.protein}`);
		if (constraints.macros.fat) parts.push(`Fat: ${constraints.macros.fat}`);
		return parts.length > 0 ? parts.join(', ') : null;
	};

	const getDietLabel = () => {
		return constraints.diet ? `Diet: ${constraints.diet}` : null;
	};

	const getPrepTimeLabel = () => {
		return constraints.prepTime ? `Under ${constraints.prepTime} min` : null;
	};

	// Handle adding ingredient
	const handleAddIngredient = () => {
		if (newIngredient.trim()) {
			addExcludedIngredient(newIngredient.trim());
			setNewIngredient('');
		}
	};

	// Quick presets for calories
	const handleCaloriesPress = () => {
		if (onEditCalories) {
			onEditCalories();
		} else {
			// Simple preset picker (can be replaced with modal later)
			Alert.alert(
				'Set Calories',
				'Choose a calorie limit:',
				[
					{ text: 'Any', onPress: () => setCalories(undefined) },
					{ text: '300 or less', onPress: () => setCalories(300) },
					{ text: '500 or less', onPress: () => setCalories(500) },
					{ text: '700 or less', onPress: () => setCalories(700) },
					{ text: '1000 or less', onPress: () => setCalories(1000) },
					{ text: 'Cancel', style: 'cancel' },
				]
			);
		}
	};

	// Quick presets for macros
	const handleMacrosPress = () => {
		if (onEditMacros) {
			onEditMacros();
		} else {
			// Placeholder - can be replaced with modal
			Alert.alert(
				'Set Macros',
				'This will open a macro editor in a future update',
				[{ text: 'OK' }]
			);
		}
	};

	// Quick presets for diet
	const handleDietPress = () => {
		if (onEditDiet) {
			onEditDiet();
		} else {
			// Simple preset picker
			Alert.alert(
				'Set Diet',
				'Choose a diet type:',
				[
					{ text: 'Any', onPress: () => setDiet(undefined) },
					{ text: 'Vegan', onPress: () => setDiet('vegan') },
					{ text: 'Vegetarian', onPress: () => setDiet('vegetarian') },
					{ text: 'Keto', onPress: () => setDiet('keto') },
					{ text: 'Paleo', onPress: () => setDiet('paleo') },
					{ text: 'High Protein', onPress: () => setDiet('high_protein') },
					{ text: 'Cancel', style: 'cancel' },
				]
			);
		}
	};

	return (
		<View style={styles.container}>
			{/* Collapsible header */}
			<TouchableOpacity 
				style={styles.header}
				onPress={toggleFilters}
				activeOpacity={0.7}
			>
				<Text style={styles.headerText}>
					{filtersCollapsed ? '🔽' : '🔼'} Filters
					{activeFilterCount > 0 && ` (${activeFilterCount} active)`}
				</Text>
			</TouchableOpacity>

			{/* Filter content - only shown when expanded */}
			{!filtersCollapsed && (
				<View style={styles.content}>
					{/* Active filter chips at top */}
					{activeFilterCount > 0 && (
						<View style={styles.chipsContainer}>
							{getCaloriesLabel() && (
								<FilterChip 
									label={getCaloriesLabel()!}
									onRemove={() => setCalories(undefined)}
								/>
							)}

							{getMacrosLabel() && (
								<FilterChip 
									label={getMacrosLabel()!}
									onRemove={() => setMacros(undefined)}
								/>
							)}

							{getDietLabel() && (
								<FilterChip 
									label={getDietLabel()!}
									onRemove={() => setDiet(undefined)}
								/>
							)}

							{getPrepTimeLabel() && (
								<FilterChip 
									label={getPrepTimeLabel()!}
									onRemove={() => setCalories(undefined)}
								/>
							)}

							{constraints.excludedIngredients.map((ingredient) => (
								<FilterChip 
									key={ingredient}
									label={`No ${ingredient}`}
									onRemove={() => removeExcludedIngredient(ingredient)}
									variant="accent"
								/>
							))}
						</View>
					)}

					{/* Always-visible filter controls */}
					<View style={styles.controlsContainer}>
						{/* Calories row */}
						<View style={styles.filterRow}>
							<Text style={styles.filterLabel}>Calories:</Text>
							<TouchableOpacity 
								style={styles.filterValue}
								onPress={handleCaloriesPress}
								activeOpacity={0.7}
							>
								<Text style={styles.filterValueText}>
									{constraints.calories ? `${constraints.calories} kcal` : 'Any'} ▼
								</Text>
							</TouchableOpacity>
						</View>

						{/* Macros row */}
						<View style={styles.filterRow}>
							<Text style={styles.filterLabel}>Macros:</Text>
							<TouchableOpacity 
								style={styles.filterValue}
								onPress={handleMacrosPress}
								activeOpacity={0.7}
							>
								<Text style={styles.filterValueText}>
									{getMacrosLabel() || 'Any'} →
								</Text>
							</TouchableOpacity>
						</View>

						{/* Diet row */}
						<View style={styles.filterRow}>
							<Text style={styles.filterLabel}>Diet:</Text>
							<TouchableOpacity 
								style={styles.filterValue}
								onPress={handleDietPress}
								activeOpacity={0.7}
							>
								<Text style={styles.filterValueText}>
									{constraints.diet || 'Any'} ▼
								</Text>
							</TouchableOpacity>
						</View>

						{/* Exclude ingredients input */}
						<View style={styles.filterRow}>
							<Text style={styles.filterLabel}>Exclude:</Text>
							<View style={styles.excludeInput}>
								<TextInput
									style={styles.textInput}
									placeholder="Add ingredient..."
									placeholderTextColor={colors.text.muted}
									value={newIngredient}
									onChangeText={setNewIngredient}
									onSubmitEditing={handleAddIngredient}
									returnKeyType="done"
								/>
								{newIngredient.trim() && (
									<TouchableOpacity onPress={handleAddIngredient}>
										<Text style={styles.addButton}>Add</Text>
									</TouchableOpacity>
								)}
							</View>
						</View>
					</View>
				</View>
			)}
		</View>
	);
}

const styles = StyleSheet.create({
	container: {
		backgroundColor: colors.background.primary,
		borderBottomWidth: 1,
		borderBottomColor: colors.border.light,
	},
	header: {
		padding: spacing.md,
	},
	headerText: {
		...typography.textStyles.body,
		color: colors.text.primary,
		fontWeight: '600',
	},
	content: {
		paddingHorizontal: spacing.md,
		paddingBottom: spacing.md,
	},
	chipsContainer: {
		flexDirection: 'row',
		flexWrap: 'wrap',
		marginBottom: spacing.md,
	},
	controlsContainer: {
		gap: spacing.md,
	},
	filterRow: {
		flexDirection: 'row',
		alignItems: 'center',
		justifyContent: 'space-between',
		marginBottom: spacing.sm,
	},
	filterLabel: {
		...typography.textStyles.label,
		color: colors.text.secondary,
		width: 80,
	},
	filterValue: {
		flex: 1,
		paddingVertical: spacing.sm,
		paddingHorizontal: spacing.md,
		backgroundColor: colors.primary.light,
		borderRadius: 8,
		borderWidth: 1,
		borderColor: colors.border.light,
	},
	filterValueText: {
		fontSize: 16,
		lineHeight: 20,
		color: colors.text.primary,
	},
	excludeInput: {
		flex: 1,
		flexDirection: 'row',
		alignItems: 'center',
		paddingHorizontal: spacing.md,
		backgroundColor: colors.primary.light,
		borderRadius: 8,
		borderWidth: 1,
		borderColor: colors.border.light,
	},
	textInput: {
		flex: 1,
		minHeight: 44,
		paddingVertical: spacing.md,
		color: colors.text.primary,
		fontSize: 16,
		lineHeight: 20,
	},
	addButton: {
		...typography.textStyles.label,
		color: colors.accent.coral,
		fontWeight: '600',
	},
});

