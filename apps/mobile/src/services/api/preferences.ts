/**
 * Preferences API Service
 * Handles user preferences CRUD operations
 */
import { apiClient } from './client';

// Types
export interface UserPreferences {
  id: string;
  user_id: string;
  dietary_restrictions: string[];
  default_constraints: {
    calories?: { min?: number; max?: number };
    macros?: {
      protein?: { min?: number; max?: number };
      carbs?: { min?: number; max?: number };
      fat?: { min?: number; max?: number };
    };
    diet?: string;
    excludedIngredients?: string[];
    prepTime?: { min?: number; max?: number };
  };
  custom_constraints: Record<string, any>;
  favorite_cuisines: string[];
  disliked_ingredients: string[];
  created_at: string;
  updated_at: string;
}

export interface UserPreferencesUpdate {
  dietary_restrictions?: string[];
  default_constraints?: Partial<UserPreferences['default_constraints']>;
  custom_constraints?: Record<string, any>;
  favorite_cuisines?: string[];
  disliked_ingredients?: string[];
}

/**
 * Get user preferences
 */
export async function getUserPreferences(): Promise<UserPreferences> {
  const response = await apiClient.get<UserPreferences>('/api/preferences/');
  return response.data;
}

/**
 * Update user preferences
 * Only provided fields will be updated
 */
export async function updateUserPreferences(preferences: UserPreferencesUpdate): Promise<UserPreferences> {
  const response = await apiClient.put<UserPreferences>('/api/preferences/', preferences);
  return response.data;
}

/**
 * Reset user preferences to defaults
 */
export async function resetUserPreferences(): Promise<void> {
  await apiClient.delete('/api/preferences/');
}

