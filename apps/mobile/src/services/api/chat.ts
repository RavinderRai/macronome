/**
 * Chat API Service
 * Handles chat workflow and chat session management
 */
import { apiClient } from './client';

// Types
export type ChatAction = 'add_constraint' | 'start_recommendation' | 'general_chat';

export interface ChatMessageRequest {
  message: string;
  chat_session_id?: string;
}

export interface ChatMessageResponse {
  response: string;
  action?: ChatAction;
  task_id?: string; // If action is START_RECOMMENDATION
  updated_constraints?: Record<string, any>; // If constraints were added
  chat_session_id: string;
}

export interface ChatSession {
  id: string;
  user_id: string;
  is_active: boolean;
  filters?: Record<string, any>;
  created_at: string;
  updated_at: string;
}

export interface ChatSessionCreate {
  filters?: Record<string, any>;
}

export interface ChatMessage {
  id: string;
  chat_session_id: string;
  message: string;
  role: 'user' | 'assistant';
  created_at: string;
}

/**
 * Send chat message
 * Processes message through AI workflow and returns response
 */
export async function sendChatMessage(request: ChatMessageRequest): Promise<ChatMessageResponse> {
  const response = await apiClient.post<ChatMessageResponse>('/api/chat/message', request);
  return response.data;
}

/**
 * Get user's chat sessions
 */
export async function getChatSessions(limit: number = 50): Promise<ChatSession[]> {
  const response = await apiClient.get<ChatSession[]>(`/api/chat/sessions?limit=${limit}`);
  return response.data;
}

/**
 * Create new chat session
 * Deactivates any existing active session
 */
export async function createChatSession(sessionData?: ChatSessionCreate): Promise<ChatSession> {
  const response = await apiClient.post<ChatSession>('/api/chat/sessions', sessionData || {});
  return response.data;
}

/**
 * Get messages for a chat session
 */
export async function getSessionMessages(sessionId: string, limit: number = 100): Promise<ChatMessage[]> {
  const response = await apiClient.get<ChatMessage[]>(`/api/chat/sessions/${sessionId}/messages?limit=${limit}`);
  return response.data;
}

