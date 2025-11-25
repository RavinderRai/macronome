import React, { useState } from 'react';
import { View, Text, TouchableOpacity, StyleSheet, ScrollView } from 'react-native';
import { colors, spacing } from '../../theme';

interface MealRecommendationCardProps {
  data: {
    recipe: {
      name: string;
      ingredients: string[];
      directions?: string;
      nutrition: {
        calories: number;
        protein: number;
        carbs: number;
        fat: number;
      };
    };
    why_it_fits: string;
    ingredient_swaps: string[];
    pantry_utilization: string[];
    recipe_instructions: string;
  };
}

export default function MealRecommendationCard({ data }: MealRecommendationCardProps) {
  const [whyExpanded, setWhyExpanded] = useState(false);
  const [instructionsExpanded, setInstructionsExpanded] = useState(false);
  const [swapsExpanded, setSwapsExpanded] = useState(false);
  const [showAllIngredients, setShowAllIngredients] = useState(false);

  const { recipe, why_it_fits, ingredient_swaps, pantry_utilization, recipe_instructions } = data;

  return (
    <View style={styles.container}>
      {/* Header with recipe name */}
      <View style={styles.header}>
        <Text style={styles.recipeName}>{recipe.name}</Text>
      </View>

      {/* Nutrition badges */}
      <View style={styles.nutritionRow}>
        <View style={styles.nutritionBadge}>
          <Text style={styles.nutritionValue}>{recipe.nutrition.calories}</Text>
          <Text style={styles.nutritionLabel}>cal</Text>
        </View>
        <View style={styles.nutritionBadge}>
          <Text style={styles.nutritionValue}>{recipe.nutrition.protein}g</Text>
          <Text style={styles.nutritionLabel}>protein</Text>
        </View>
        <View style={styles.nutritionBadge}>
          <Text style={styles.nutritionValue}>{recipe.nutrition.carbs}g</Text>
          <Text style={styles.nutritionLabel}>carbs</Text>
        </View>
        <View style={styles.nutritionBadge}>
          <Text style={styles.nutritionValue}>{recipe.nutrition.fat}g</Text>
          <Text style={styles.nutritionLabel}>fat</Text>
        </View>
      </View>

      {/* Divider */}
      <View style={styles.divider} />

      {/* Why it fits - Collapsible */}
      <TouchableOpacity 
        style={styles.sectionHeader}
        onPress={() => setWhyExpanded(!whyExpanded)}
        activeOpacity={0.7}
      >
        <Text style={styles.sectionTitle}>Why this fits</Text>
        <Text style={styles.expandIcon}>{whyExpanded ? '▼' : '▶'}</Text>
      </TouchableOpacity>
      {whyExpanded && (
        <View style={styles.sectionContent}>
          <Text style={styles.bodyText}>{why_it_fits}</Text>
        </View>
      )}

      {/* Divider */}
      <View style={styles.divider} />

      {/* Ingredients - Always visible with expand option */}
      <View style={styles.section}>
        <Text style={styles.sectionTitle}>Ingredients</Text>
        <View style={styles.ingredientsList}>
          {(showAllIngredients ? recipe.ingredients : recipe.ingredients.slice(0, 8)).map((ingredient, index) => (
            <Text key={index} style={styles.ingredientItem}>
              • {ingredient}
            </Text>
          ))}
          {recipe.ingredients.length > 8 && (
            <TouchableOpacity 
              onPress={() => setShowAllIngredients(!showAllIngredients)}
              activeOpacity={0.7}
            >
              <Text style={styles.showMoreText}>
                {showAllIngredients 
                  ? '▲ Show less' 
                  : `▼ Show ${recipe.ingredients.length - 8} more ingredients`
                }
              </Text>
            </TouchableOpacity>
          )}
        </View>
      </View>

      {/* Divider */}
      <View style={styles.divider} />

      {/* Ingredient swaps - Collapsible (if available) */}
      {ingredient_swaps && ingredient_swaps.length > 0 && (
        <>
          <TouchableOpacity 
            style={styles.sectionHeader}
            onPress={() => setSwapsExpanded(!swapsExpanded)}
            activeOpacity={0.7}
          >
            <Text style={styles.sectionTitle}>Ingredient Swaps</Text>
            <Text style={styles.expandIcon}>{swapsExpanded ? '▼' : '▶'}</Text>
          </TouchableOpacity>
          {swapsExpanded && (
            <View style={styles.sectionContent}>
              {ingredient_swaps.map((swap, index) => (
                <Text key={index} style={styles.bulletItem}>
                  • {swap}
                </Text>
              ))}
            </View>
          )}
          <View style={styles.divider} />
        </>
      )}

      {/* Instructions - Collapsible */}
      <TouchableOpacity 
        style={styles.sectionHeader}
        onPress={() => setInstructionsExpanded(!instructionsExpanded)}
        activeOpacity={0.7}
      >
        <Text style={styles.sectionTitle}>Instructions</Text>
        <Text style={styles.expandIcon}>{instructionsExpanded ? '▼' : '▶'}</Text>
      </TouchableOpacity>
      {instructionsExpanded && (
        <ScrollView style={styles.instructionsContent}>
          <Text style={styles.bodyText}>{recipe_instructions || recipe.directions}</Text>
        </ScrollView>
      )}

      {/* Pantry utilization badge (if available) */}
      {pantry_utilization && pantry_utilization.length > 0 && (
        <View style={styles.pantryBadge}>
          <Text style={styles.pantryText}>
            ✓ Using {pantry_utilization.length} pantry items
          </Text>
        </View>
      )}
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    backgroundColor: colors.primary.light,
    borderRadius: 12,
    padding: spacing.md,
    marginBottom: spacing.md,
    borderWidth: 1,
    borderColor: colors.border.light,
  },
  header: {
    marginBottom: spacing.md,
  },
  recipeName: {
    fontSize: 20,
    fontWeight: '700',
    color: colors.text.primary,
    lineHeight: 28,
  },
  nutritionRow: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    marginBottom: spacing.md,
    gap: spacing.xs,
  },
  nutritionBadge: {
    flex: 1,
    backgroundColor: colors.primary.dark,
    paddingVertical: spacing.sm,
    paddingHorizontal: spacing.xs,
    borderRadius: 8,
    alignItems: 'center',
    borderWidth: 1,
    borderColor: colors.accent.coral,
  },
  nutritionValue: {
    fontSize: 16,
    fontWeight: '700',
    color: colors.accent.coral,
    marginBottom: 2,
  },
  nutritionLabel: {
    fontSize: 11,
    color: colors.text.secondary,
    textTransform: 'uppercase',
  },
  divider: {
    height: 1,
    backgroundColor: colors.border.medium,
    marginVertical: spacing.sm,
  },
  sectionHeader: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    paddingVertical: spacing.sm,
  },
  sectionTitle: {
    fontSize: 16,
    fontWeight: '600',
    color: colors.text.primary,
  },
  expandIcon: {
    fontSize: 12,
    color: colors.accent.coral,
  },
  section: {
    paddingVertical: spacing.sm,
  },
  sectionContent: {
    paddingVertical: spacing.sm,
    paddingLeft: spacing.sm,
  },
  bodyText: {
    fontSize: 14,
    lineHeight: 20,
    color: colors.text.secondary,
  },
  ingredientsList: {
    marginTop: spacing.xs,
  },
  ingredientItem: {
    fontSize: 14,
    lineHeight: 22,
    color: colors.text.secondary,
    marginBottom: spacing.xs,
  },
  moreText: {
    fontSize: 12,
    color: colors.text.muted,
    fontStyle: 'italic',
    marginTop: spacing.xs,
  },
  showMoreText: {
    fontSize: 13,
    color: colors.accent.coral,
    fontWeight: '600',
    marginTop: spacing.sm,
  },
  bulletItem: {
    fontSize: 14,
    lineHeight: 22,
    color: colors.text.secondary,
    marginBottom: spacing.xs,
  },
  instructionsContent: {
    paddingVertical: spacing.sm,
    paddingLeft: spacing.sm,
    maxHeight: 300,
  },
  pantryBadge: {
    backgroundColor: colors.accent.coral,
    paddingVertical: spacing.xs,
    paddingHorizontal: spacing.sm,
    borderRadius: 6,
    marginTop: spacing.md,
    alignSelf: 'flex-start',
  },
  pantryText: {
    fontSize: 12,
    fontWeight: '600',
    color: colors.text.primary,
  },
});

