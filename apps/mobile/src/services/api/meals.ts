/**
 * Meals API Service
 * Handles meal recommendations and meal history
 */
import { apiClient } from './client';

// Types
export interface MealRecommendRequest {
  user_query?: string;
  constraints?: Record<string, any>;
}

export interface MealRecommendResponse {
  task_id: string;
  message: string;
}

export type TaskStatus = 'pending' | 'started' | 'success' | 'failure';

export interface MealRecommendStatusResponse {
  status: TaskStatus;
  result?: {
    name: string;
    description: string;
    ingredients: string[];
    instructions: string[];
    reasoning: string;
    meal_data: Record<string, any>;
  };
  error?: string;
}

export interface MealHistory {
  id: string;
  user_id: string;
  chat_session_id?: string;
  name: string;
  description: string;
  ingredients: string[];
  reasoning: string;
  meal_data: Record<string, any>;
  accepted: boolean;
  rating?: number;
  created_at: string;
  updated_at: string;
}

export interface MealHistoryCreate {
  name: string;
  description: string;
  ingredients: string[];
  reasoning: string;
  meal_data: Record<string, any>;
  accepted: boolean;
}

export interface MealRatingUpdate {
  rating: number; // 1-5
}

/**
 * Request meal recommendation (async)
 * Returns task_id for polling status
 */
export async function recommendMeal(request: MealRecommendRequest): Promise<MealRecommendResponse> {
  const response = await apiClient.post<MealRecommendResponse>('/api/meals/recommend', request);
  return response.data;
}

/**
 * Poll meal recommendation status
 */
export async function getRecommendationStatus(taskId: string): Promise<MealRecommendStatusResponse> {
  const response = await apiClient.get<MealRecommendStatusResponse>(`/api/meals/recommend/${taskId}`);
  return response.data;
}

/**
 * Get meal recommendation history
 */
export async function getMealHistory(limit: number = 50): Promise<MealHistory[]> {
  const response = await apiClient.get<MealHistory[]>(`/api/meals/history?limit=${limit}`);
  return response.data;
}

/**
 * Save meal to history
 */
export async function saveMealToHistory(meal: MealHistoryCreate, chatSessionId?: string): Promise<{ message: string; meal: MealHistory }> {
  const response = await apiClient.post<{ message: string; meal: MealHistory }>(
    `/api/meals/history${chatSessionId ? `?chat_session_id=${chatSessionId}` : ''}`,
    meal
  );
  return response.data;
}

/**
 * Update meal rating
 */
export async function updateMealRating(mealId: string, rating: number): Promise<{ message: string; meal: MealHistory }> {
  const response = await apiClient.put<{ message: string; meal: MealHistory }>(
    `/api/meals/history/${mealId}/rating`,
    { rating }
  );
  return response.data;
}

