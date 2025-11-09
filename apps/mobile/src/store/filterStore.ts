import { create } from 'zustand';
import type { FilterConstraints, FilterState } from '../types/filters';

// Extend FilterState with actions
interface FilterStore extends FilterState {
  // Actions
  setCalories: (calories: number | undefined) => void;
  setMacros: (macros: FilterConstraints['macros']) => void;
  setDiet: (diet: string | undefined) => void;
  setExcludedIngredients: (ingredients: string[]) => void;
  addExcludedIngredient: (ingredient: string) => void;
  removeExcludedIngredient: (ingredient: string) => void;
  setPrepTime: (prepTime: number | undefined) => void;
  setConstraints: (constraints: FilterConstraints) => void;
  clearFilters: () => void;
}

// Create the store
export const useFilterStore = create<FilterStore>((set) => ({
  // Initial state
  constraints: {
    excludedIngredients: [], // Always initialize as empty array
  },

  // Actions
  setCalories: (calories) => {
    set((state) => ({
      constraints: {
        ...state.constraints,
        calories,
      },
    }));
  },

  setMacros: (macros) => {
    set((state) => ({
      constraints: {
        ...state.constraints,
        macros,
      },
    }));
  },

  setDiet: (diet) => {
    set((state) => ({
      constraints: {
        ...state.constraints,
        diet,
      },
    }));
  },

  setExcludedIngredients: (ingredients) => {
    set((state) => ({
      constraints: {
        ...state.constraints,
        excludedIngredients: ingredients,
      },
    }));
  },

  addExcludedIngredient: (ingredient) => {
    set((state) => {
      const current = state.constraints.excludedIngredients || [];
      if (!current.includes(ingredient)) {
        return {
          constraints: {
            ...state.constraints,
            excludedIngredients: [...current, ingredient],
          },
        };
      }
      return state; // Already exists, no change
    });
  },

  removeExcludedIngredient: (ingredient) => {
    set((state) => ({
      constraints: {
        ...state.constraints,
        excludedIngredients: (state.constraints.excludedIngredients || []).filter(
          (item) => item !== ingredient
        ),
      },
    }));
  },

  setPrepTime: (prepTime) => {
    set((state) => ({
      constraints: {
        ...state.constraints,
        prepTime,
      },
    }));
  },

  setConstraints: (constraints) => {
    set({ constraints });
  },

  clearFilters: () => {
    set({
      constraints: {
        excludedIngredients: [],
      },
    });
  },
}));