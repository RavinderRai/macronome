/**
 * Filter Section Component
 * Collapsible section with always-visible preset filter controls
 * App handles preset filters only, chat will handle more complex filter requests
 */

import React from 'react';
import { View, Text, TouchableOpacity, StyleSheet, TextInput, Alert, Modal } from 'react-native';
import { colors } from '../../theme';
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
	const [showMacrosModal, setShowMacrosModal] = React.useState(false);
	const [macroCarbs, setMacroCarbs] = React.useState('');
	const [macroProtein, setMacroProtein] = React.useState('');
	const [macroFat, setMacroFat] = React.useState('');

	// Get state from Zustand stores
	const constraints = useFilterStore((state) => state.constraints);
	const setCalories = useFilterStore((state) => state.setCalories);
	const setMacros = useFilterStore((state) => state.setMacros);
	const setDiet = useFilterStore((state) => state.setDiet);
	const addAllergy = useFilterStore((state) => state.addAllergy);
	const removeAllergy = useFilterStore((state) => state.removeAllergy);
	const setPrepTime = useFilterStore((state) => state.setPrepTime);
	const setMealType = useFilterStore((state) => state.setMealType);
	
	const filtersCollapsed = useUIStore((state) => state.filtersCollapsed);
	const toggleFilters = useUIStore((state) => state.toggleFilters);

	// Count active filters
	const activeFilterCount = [
		constraints.calories !== undefined,
		constraints.macros !== undefined,
		constraints.diet !== undefined,
		constraints.allergies.length > 0,
		constraints.prepTime !== undefined,
		constraints.mealType !== undefined,
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

	const getMealTypeLabel = () => {
		return constraints.mealType ? `Meal: ${constraints.mealType}` : null;
	};

	// Handle adding ingredient
	const handleAddIngredient = () => {
		if (newIngredient.trim()) {
			addAllergy(newIngredient.trim());
			setNewIngredient('');
		}
	};

	// Handle calories input - only allow integers
	const handleCaloriesChange = (text: string) => {
		// Remove any non-numeric characters
		const numericValue = text.replace(/[^0-9]/g, '');
		
		if (numericValue === '') {
			setCalories(undefined);
		} else {
			const caloriesValue = parseInt(numericValue, 10);
			if (!isNaN(caloriesValue)) {
				setCalories(caloriesValue);
			}
		}
	};

	// Handle macros modal
	const handleMacrosPress = () => {
		if (onEditMacros) {
			onEditMacros();
		} else {
			// Initialize modal with current values
			const currentMacros = constraints.macros;
			setMacroCarbs(currentMacros?.carbs?.toString() || '');
			setMacroProtein(currentMacros?.protein?.toString() || '');
			setMacroFat(currentMacros?.fat?.toString() || '');
			setShowMacrosModal(true);
		}
	};

	// Handle macro input changes - only allow integers
	const handleMacroChange = (
		value: string,
		setter: (value: string) => void
	) => {
		const numericValue = value.replace(/[^0-9]/g, '');
		setter(numericValue);
	};

	// Save macros
	const handleSaveMacros = () => {
		const macros = {
			carbs: macroCarbs ? parseInt(macroCarbs, 10) : undefined,
			protein: macroProtein ? parseInt(macroProtein, 10) : undefined,
			fat: macroFat ? parseInt(macroFat, 10) : undefined,
		};

		// Only set macros if at least one value is provided
		if (macros.carbs || macros.protein || macros.fat) {
			setMacros(macros);
		} else {
			setMacros(undefined);
		}

		setShowMacrosModal(false);
	};

	// Clear macros
	const handleClearMacros = () => {
		setMacros(undefined);
		setMacroCarbs('');
		setMacroProtein('');
		setMacroFat('');
		setShowMacrosModal(false);
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

	// Quick presets for meal type
	const handleMealTypePress = () => {
		Alert.alert(
			'Set Meal Type',
			'Choose a meal type:',
			[
				{ text: 'Any', onPress: () => setMealType(undefined) },
				{ text: 'Breakfast', onPress: () => setMealType('breakfast') },
				{ text: 'Lunch', onPress: () => setMealType('lunch') },
				{ text: 'Snack', onPress: () => setMealType('snack') },
				{ text: 'Dinner', onPress: () => setMealType('dinner') },
				{ text: 'Dessert', onPress: () => setMealType('dessert') },
				{ text: 'Cancel', style: 'cancel' },
			]
		);
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
								<View style={styles.chipWrapper}>
								<FilterChip 
									label={getCaloriesLabel()!}
									onRemove={() => setCalories(undefined)}
								/>
								</View>
							)}

							{getMacrosLabel() && (
								<View style={styles.chipWrapper}>
								<FilterChip 
									label={getMacrosLabel()!}
									onRemove={() => setMacros(undefined)}
								/>
								</View>
							)}

							{getDietLabel() && (
								<View style={styles.chipWrapper}>
								<FilterChip 
									label={getDietLabel()!}
									onRemove={() => setDiet(undefined)}
								/>
								</View>
							)}

							{getPrepTimeLabel() && (
								<View style={styles.chipWrapper}>
								<FilterChip 
									label={getPrepTimeLabel()!}
										onRemove={() => setPrepTime(undefined)}
									/>
								</View>
							)}

							{getMealTypeLabel() && (
								<View style={styles.chipWrapper}>
									<FilterChip 
										label={getMealTypeLabel()!}
										onRemove={() => setMealType(undefined)}
								/>
								</View>
							)}

							{constraints.allergies.map((ingredient) => (
								<View key={ingredient} style={styles.chipWrapper}>
								<FilterChip 
									label={`No ${ingredient}`}
									onRemove={() => removeAllergy(ingredient)}
									variant="accent"
								/>
								</View>
							))}
						</View>
					)}

					{/* Always-visible filter controls */}
					<View style={styles.controlsContainer}>
						{/* Row 1: Calories | Macros */}
						<View style={styles.filterRow}>
							<View style={styles.filterColumn}>
							<Text style={styles.filterLabel}>Calories:</Text>
								<View style={styles.caloriesInput}>
									<TextInput
										style={styles.caloriesTextInput}
										placeholder="Any"
										placeholderTextColor={colors.text.muted}
										value={constraints.calories !== undefined ? constraints.calories.toString() : ''}
										onChangeText={handleCaloriesChange}
										keyboardType="number-pad"
										returnKeyType="done"
									/>
									{constraints.calories !== undefined && (
										<Text style={styles.caloriesUnit}>kcal</Text>
									)}
								</View>
						</View>

							<View style={styles.filterColumn}>
							<Text style={styles.filterLabel}>Macros:</Text>
							<TouchableOpacity 
								style={styles.filterValue}
								onPress={handleMacrosPress}
								activeOpacity={0.7}
							>
								<Text style={styles.filterValueText}>
									{getMacrosLabel() || 'Any'}
								</Text>
							</TouchableOpacity>
							</View>
						</View>

						{/* Row 2: Diet | Prep Time */}
						<View style={styles.filterRow}>
							<View style={styles.filterColumn}>
							<Text style={styles.filterLabel}>Diet:</Text>
							<TouchableOpacity 
								style={styles.filterValue}
								onPress={handleDietPress}
								activeOpacity={0.7}
							>
								<Text style={styles.filterValueText}>
									{constraints.diet || 'Any'}
								</Text>
							</TouchableOpacity>
						</View>

							<View style={styles.filterColumn}>
								<Text style={styles.filterLabel}>Prep Time:</Text>
								<TouchableOpacity 
									style={styles.filterValue}
									onPress={() => {
										Alert.alert(
											'Set Prep Time',
											'Choose maximum prep time:',
											[
												{ text: 'Any', onPress: () => setPrepTime(undefined) },
												{ text: '15 min', onPress: () => setPrepTime(15) },
												{ text: '30 min', onPress: () => setPrepTime(30) },
												{ text: '45 min', onPress: () => setPrepTime(45) },
												{ text: '60 min', onPress: () => setPrepTime(60) },
												{ text: 'Cancel', style: 'cancel' },
											]
										);
									}}
									activeOpacity={0.7}
								>
									<Text style={styles.filterValueText}>
										{constraints.prepTime ? `Under ${constraints.prepTime} min` : 'Any'}
									</Text>
								</TouchableOpacity>
							</View>
						</View>

						{/* Row 3: Meal Type | Allergies */}
						<View style={styles.filterRow}>
							<View style={styles.filterColumn}>
								<Text style={styles.filterLabel}>Meal Type:</Text>
								<TouchableOpacity 
									style={styles.filterValue}
									onPress={handleMealTypePress}
									activeOpacity={0.7}
								>
									<Text style={styles.filterValueText}>
										{constraints.mealType ? constraints.mealType.charAt(0).toUpperCase() + constraints.mealType.slice(1) : 'Any'}
									</Text>
								</TouchableOpacity>
							</View>

							<View style={styles.filterColumn}>
								<Text style={styles.filterLabel}>Allergies:</Text>
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
				</View>
			)}

			{/* Macros Editor Modal */}
			<Modal
				visible={showMacrosModal}
				transparent={true}
				animationType="fade"
				onRequestClose={() => setShowMacrosModal(false)}
			>
				<View style={styles.modalOverlay}>
					<View style={styles.modalContent}>
						<Text style={styles.modalTitle}>Set Macros</Text>
						<Text style={styles.modalSubtitle}>Enter target macros in grams</Text>

						{/* Carbs Input */}
						<View style={styles.macroInputContainer}>
							<Text style={styles.macroLabel}>Carbs (g):</Text>
							<TextInput
								style={styles.macroInput}
								placeholder="Any"
								placeholderTextColor={colors.text.muted}
								value={macroCarbs}
								onChangeText={(text) => handleMacroChange(text, setMacroCarbs)}
								keyboardType="number-pad"
								returnKeyType="next"
							/>
						</View>

						{/* Protein Input */}
						<View style={styles.macroInputContainer}>
							<Text style={styles.macroLabel}>Protein (g):</Text>
							<TextInput
								style={styles.macroInput}
								placeholder="Any"
								placeholderTextColor={colors.text.muted}
								value={macroProtein}
								onChangeText={(text) => handleMacroChange(text, setMacroProtein)}
								keyboardType="number-pad"
								returnKeyType="next"
							/>
						</View>

						{/* Fat Input */}
						<View style={styles.macroInputContainer}>
							<Text style={styles.macroLabel}>Fat (g):</Text>
							<TextInput
								style={styles.macroInput}
								placeholder="Any"
								placeholderTextColor={colors.text.muted}
								value={macroFat}
								onChangeText={(text) => handleMacroChange(text, setMacroFat)}
								keyboardType="number-pad"
								returnKeyType="done"
							/>
						</View>

						{/* Modal Buttons */}
						<View style={styles.modalButtons}>
							<TouchableOpacity
								style={[styles.modalButton, styles.modalButtonCancel]}
								onPress={() => setShowMacrosModal(false)}
							>
								<Text style={styles.modalButtonCancelText}>Cancel</Text>
							</TouchableOpacity>
							<TouchableOpacity
								style={[styles.modalButton, styles.modalButtonClear]}
								onPress={handleClearMacros}
							>
								<Text style={styles.modalButtonClearText}>Clear</Text>
							</TouchableOpacity>
							<TouchableOpacity
								style={[styles.modalButton, styles.modalButtonSave]}
								onPress={handleSaveMacros}
							>
								<Text style={styles.modalButtonSaveText}>Save</Text>
							</TouchableOpacity>
						</View>
					</View>
				</View>
			</Modal>
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
		fontSize: 16,
		lineHeight: 24,
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
		justifyContent: 'space-between',
	},
	chipWrapper: {
		width: '48%',
		marginBottom: spacing.sm,
	},
	controlsContainer: {
		gap: spacing.md,
	},
	filterRow: {
		flexDirection: 'row',
		justifyContent: 'space-between',
		marginBottom: spacing.md,
		gap: spacing.sm,
	},
	filterColumn: {
		flex: 1,
		gap: spacing.xs,
	},
	filterLabel: {
		fontSize: 14,
		fontWeight: '500',
		lineHeight: 20,
		color: colors.text.secondary,
		marginBottom: spacing.xs,
	},
	filterValue: {
		paddingVertical: spacing.sm,
		paddingHorizontal: spacing.md,
		backgroundColor: colors.primary.light,
		borderRadius: 8,
		borderWidth: 1,
		borderColor: colors.border.light,
		minHeight: 44,
		justifyContent: 'center',
	},
	filterValueText: {
		fontSize: 16,
		lineHeight: 20,
		color: colors.text.primary,
	},
	caloriesInput: {
		flexDirection: 'row',
		alignItems: 'center',
		paddingVertical: spacing.sm,
		paddingHorizontal: spacing.md,
		backgroundColor: colors.primary.light,
		borderRadius: 8,
		borderWidth: 1,
		borderColor: colors.border.light,
		minHeight: 44,
		justifyContent: 'center',
	},
	caloriesTextInput: {
		flex: 1,
		color: colors.text.primary,
		fontSize: 16,
		lineHeight: 20,
		textAlign: 'left',
		padding: 0,
	},
	caloriesUnit: {
		fontSize: 14,
		color: colors.text.secondary,
		marginLeft: spacing.xs,
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
		fontSize: 14,
		fontWeight: '600',
		lineHeight: 20,
		color: colors.accent.coral,
	},
	modalOverlay: {
		flex: 1,
		backgroundColor: 'rgba(0, 0, 0, 0.5)',
		justifyContent: 'center',
		alignItems: 'center',
	},
	modalContent: {
		backgroundColor: colors.background.primary,
		borderRadius: 16,
		padding: spacing.lg,
		width: '85%',
		maxWidth: 400,
		borderWidth: 1,
		borderColor: colors.border.light,
	},
	modalTitle: {
		fontSize: 20,
		fontWeight: '700',
		color: colors.text.primary,
		marginBottom: spacing.xs,
		textAlign: 'center',
	},
	modalSubtitle: {
		fontSize: 14,
		color: colors.text.secondary,
		marginBottom: spacing.lg,
		textAlign: 'center',
	},
	macroInputContainer: {
		marginBottom: spacing.md,
	},
	macroLabel: {
		fontSize: 14,
		fontWeight: '500',
		color: colors.text.secondary,
		marginBottom: spacing.xs,
	},
	macroInput: {
		backgroundColor: colors.primary.light,
		borderRadius: 8,
		borderWidth: 1,
		borderColor: colors.border.light,
		paddingVertical: spacing.sm,
		paddingHorizontal: spacing.md,
		color: colors.text.primary,
		fontSize: 16,
		minHeight: 44,
	},
	modalButtons: {
		flexDirection: 'row',
		justifyContent: 'space-between',
		marginTop: spacing.md,
		gap: spacing.sm,
	},
	modalButton: {
		flex: 1,
		paddingVertical: spacing.md,
		borderRadius: 8,
		alignItems: 'center',
		justifyContent: 'center',
	},
	modalButtonCancel: {
		backgroundColor: colors.primary.light,
		borderWidth: 1,
		borderColor: colors.border.light,
	},
	modalButtonCancelText: {
		color: colors.text.primary,
		fontSize: 16,
		fontWeight: '600',
	},
	modalButtonClear: {
		backgroundColor: 'transparent',
		borderWidth: 1,
		borderColor: colors.border.light,
	},
	modalButtonClearText: {
		color: colors.text.secondary,
		fontSize: 16,
		fontWeight: '600',
	},
	modalButtonSave: {
		backgroundColor: colors.accent.coral,
	},
	modalButtonSaveText: {
		color: '#FFFFFF',
		fontSize: 16,
		fontWeight: '600',
	},
});

