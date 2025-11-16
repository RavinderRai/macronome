/**
 * Users API Service
 * Handles user initialization and management
 */
import { apiClient } from './client';

export interface InitializeUserResponse {
  message: string;
  user_id: string;
  already_exists: boolean;
  preferences_id?: string;
  chat_session_id?: string;
}

export interface UserStatusResponse {
  user_id: string;
  is_initialized: boolean;
  has_preferences: boolean;
  has_active_session: boolean;
}

/**
 * Initialize user records after sign-up
 * Creates user_preferences and chat_session in Supabase
 * Idempotent - safe to call multiple times
 */
export async function initializeUser(): Promise<InitializeUserResponse> {
  const response = await apiClient.post<InitializeUserResponse>('/api/users/initialize');
  return response.data;
}

/**
 * Get current user's initialization status
 * Useful for checking if initialization is needed after sign-in
 */
export async function getUserStatus(): Promise<UserStatusResponse> {
  const response = await apiClient.get<UserStatusResponse>('/api/users/me');
  return response.data;
}

