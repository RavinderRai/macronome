import React from 'react';
import { View, Text, Image, StyleSheet } from 'react-native';
import { colors } from '../../theme';
import { typography } from '../../theme';
import { spacing } from '../../theme';
import type { Meal } from '../../types/chat';

interface MealCardProps {
	meal: Meal;
}

export default function MealCard({ meal }: MealCardProps) {
	return (
		<View style={styles.container}>
			{/* Meal image (if available) */}
			{meal.imageUrl && (
				<Image 
					source={{ uri: meal.imageUrl }}
					style={styles.image}
					resizeMode="cover"
				/>
			)}
			
			{/* Meal details */}
			<View style={styles.content}>
				{/* Title */}
				<Text style={styles.title}>{meal.name}</Text>
				
				{/* Description */}
				{meal.description && (
					<Text style={styles.description}>{meal.description}</Text>
				)}

				{/* Ingredients */}
				{meal.ingredients.length > 0 && (
					<View style={styles.ingredientsSection}>
						<Text style={styles.sectionTitle}>Ingredients:</Text>
						{meal.ingredients.slice(0, 5).map((ingredient, index) => (
							<Text key={index} style={styles.ingredient}>
								• {ingredient}
							</Text>
						))}
						{meal.ingredients.length > 5 && (
							<Text style={styles.moreText}>
								+ {meal.ingredients.length - 5} more
							</Text>
						)}
					</View>
				)}
				
				{/* Why it fits explanation */}
				{meal.reasoning && (
					<View style={styles.explanationSection}>
						<Text style={styles.sectionTitle}>Why this fits:</Text>
						<Text style={styles.explanation}>{meal.reasoning}</Text>
					</View>
				)}
			</View>
		</View>
	);
}


const styles = StyleSheet.create({
	container: {
		backgroundColor: colors.background.card,
		borderRadius: 12,
		marginBottom: spacing.md,
		overflow: 'hidden',                  // Clips image to border radius
	},
	image: {
		width: '100%',
		height: 200,
	},
	content: {
		padding: spacing.md,
	},
	title: {
		...typography.textStyles.h3,
		color: colors.text.inverse,
		marginBottom: spacing.sm,
	},
	description: {
		...typography.textStyles.body,
		color: colors.text.inverse,
		marginBottom: spacing.md,
	},
	metaRow: {
		flexDirection: 'row',
		gap: spacing.md,
		marginBottom: spacing.md,
	},
	metaText: {
		...typography.textStyles.caption,
		color: colors.text.inverse,
	},
	ingredientsSection: {
		marginBottom: spacing.md,
	},
	sectionTitle: {
		...typography.textStyles.label,
		color: colors.text.inverse,
		fontWeight: '600',
		marginBottom: spacing.xs,
	},
	ingredient: {
		...typography.textStyles.bodySmall,
		color: colors.text.inverse,
		marginBottom: spacing.xs,
	},
	moreText: {
		...typography.textStyles.caption,
		color: colors.text.inverse,
		fontStyle: 'italic',
		marginTop: spacing.xs,
	},
	explanationSection: {
		padding: spacing.md,
		backgroundColor: colors.accent.coral,
		borderRadius: 8,
		marginTop: spacing.sm,
	},
	explanation: {
		...typography.textStyles.bodySmall,
		color: colors.text.primary,
	},
});