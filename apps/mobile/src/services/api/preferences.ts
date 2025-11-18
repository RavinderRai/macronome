/**
 * Preferences API Service
 * Handles user preferences CRUD operations
 */
import { apiClient } from './client';
import { FilterConstraints } from '../../types/filters';

// Types - matches backend UserPreferences model
export interface MacroConstraints {
  carbs?: number;
  protein?: number;
  fat?: number;
}

export interface UserPreferences {
  id: string;
  user_id: string;
  calories?: number;
  macros?: MacroConstraints;
    diet?: string;
  allergies: string[];
  prep_time?: number;
  meal_type?: string;
  custom_constraints: Record<string, any>;
  created_at: string;
  updated_at: string;
}

/**
 * Get user preferences
 */
export async function getUserPreferences(): Promise<UserPreferences> {
  const response = await apiClient.get<UserPreferences>('/api/preferences/');
  return response.data;
}

/**
 * Update user preferences (partial update)
 * Only provided fields will be updated
 * Accepts FilterConstraints (frontend format with camelCase: prepTime, mealType)
 */
export async function updateUserPreferences(preferences: FilterConstraints): Promise<UserPreferences> {
  const response = await apiClient.patch<UserPreferences>('/api/preferences/', preferences);
  return response.data;
}

/**
 * Reset user preferences to defaults
 */
export async function resetUserPreferences(): Promise<void> {
  await apiClient.delete('/api/preferences/');
}

