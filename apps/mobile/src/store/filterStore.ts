import { create } from 'zustand';
import type { FilterConstraints, FilterState } from '../types/filters';
import { updateUserPreferences } from '../services/api/preferences';

// Debounce timer for API calls
let debounceTimer: NodeJS.Timeout | null = null;
const DEBOUNCE_DELAY = 500; // 500ms delay before API call

// Helper function to sync constraints to backend
async function syncConstraintsToBackend(constraints: FilterConstraints) {
  try {
    // Clear existing timer
    if (debounceTimer) {
      clearTimeout(debounceTimer);
    }

    // Set new timer
    debounceTimer = setTimeout(async () => {
      try {
        await updateUserPreferences(constraints);
        console.log('✅ Synced filter constraints to backend');
      } catch (error) {
        console.error('❌ Failed to sync filter constraints to backend:', error);
        // Don't throw - we don't want to break the UI if API call fails
      }
    }, DEBOUNCE_DELAY);
  } catch (error) {
    console.error('❌ Error setting up debounce timer:', error);
  }
}

// Extend FilterState with actions
interface FilterStore extends FilterState {
  // Actions
  setCalories: (calories: number | undefined) => void;
  setMacros: (macros: FilterConstraints['macros']) => void;
  setDiet: (diet: string | undefined) => void;
  setAllergies: (allergies: string[]) => void;
  addAllergy: (ingredient: string) => void;
  removeAllergy: (ingredient: string) => void;
  setPrepTime: (prepTime: number | undefined) => void;
  setMealType: (mealType: string | undefined) => void;
  setConstraints: (constraints: FilterConstraints) => void;
  setConstraintsFromBackend: (constraints: FilterConstraints) => void; // Update without API call
  clearFilters: () => void;
}

// Create the store
export const useFilterStore = create<FilterStore>((set, get) => ({
  // Initial state
  constraints: {
    allergies: [], // Always initialize as empty array
  },

  // Actions
  setCalories: (calories) => {
    set((state) => {
      const newConstraints = {
        ...state.constraints,
        calories,
      };
      syncConstraintsToBackend(newConstraints);
      return { constraints: newConstraints };
    });
  },

  setMacros: (macros) => {
    set((state) => {
      const newConstraints = {
        ...state.constraints,
        macros,
      };
      syncConstraintsToBackend(newConstraints);
      return { constraints: newConstraints };
    });
  },

  setDiet: (diet) => {
    set((state) => {
      const newConstraints = {
        ...state.constraints,
        diet,
      };
      syncConstraintsToBackend(newConstraints);
      return { constraints: newConstraints };
    });
  },

  setAllergies: (allergies) => {
    set((state) => {
      const newConstraints = {
        ...state.constraints,
        allergies,
      };
      syncConstraintsToBackend(newConstraints);
      return { constraints: newConstraints };
    });
  },

  addAllergy: (ingredient) => {
    set((state) => {
      const current = state.constraints.allergies || [];
      if (!current.includes(ingredient)) {
        const newConstraints = {
            ...state.constraints,
          allergies: [...current, ingredient],
        };
        syncConstraintsToBackend(newConstraints);
        return { constraints: newConstraints };
      }
      return state; // Already exists, no change
    });
  },

  removeAllergy: (ingredient) => {
    set((state) => {
      const newConstraints = {
        ...state.constraints,
        allergies: (state.constraints.allergies || []).filter(
          (item) => item !== ingredient
        ),
      };
      syncConstraintsToBackend(newConstraints);
      return { constraints: newConstraints };
    });
  },

  setPrepTime: (prepTime) => {
    set((state) => {
      const newConstraints = {
        ...state.constraints,
        prepTime,
      };
      syncConstraintsToBackend(newConstraints);
      return { constraints: newConstraints };
    });
  },

  setMealType: (mealType) => {
    set((state) => {
      const newConstraints = {
        ...state.constraints,
        mealType,
      };
      syncConstraintsToBackend(newConstraints);
      return { constraints: newConstraints };
    });
  },

  setConstraints: (constraints) => {
    set({ constraints });
    syncConstraintsToBackend(constraints);
  },

  setConstraintsFromBackend: (constraints) => {
    // Update constraints from backend without triggering API call
    // Used when chat updates constraints (backend already saved them)
    set({ constraints });
  },

  clearFilters: () => {
    const clearedConstraints = {
      allergies: [],
    };
    set({ constraints: clearedConstraints });
    syncConstraintsToBackend(clearedConstraints);
  },
}));