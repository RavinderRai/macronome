/**
 * API Client
 * Axios instance configured with base URL and auth interceptors
 */
import axios from 'axios';
import { ENV } from '../../utils/env';
import { tokenManager } from '../auth/tokenManager';

// Create axios instance with base config
export const apiClient = axios.create({
  baseURL: ENV.apiBaseUrl,
  timeout: 30000, // 30 seconds
  headers: {
    'Content-Type': 'application/json',
  },
});

// Request interceptor - add auth token to all requests
apiClient.interceptors.request.use(
  async (config) => {
    try {
      const token = await tokenManager.getToken();
      if (token) {
        config.headers.Authorization = `Bearer ${token}`;
        // Debug: Log token presence (don't log full token for security)
        console.log('🔑 Adding auth token to request:', config.url);
      } else {
        console.warn('⚠️ No token available for request:', config.url);
      }
    } catch (error) {
      console.error('Failed to get auth token:', error);
    }
    return config;
  },
  (error) => {
    return Promise.reject(error);
  }
);

// Response interceptor - handle common errors
apiClient.interceptors.response.use(
  (response) => response,
  async (error) => {
    if (error.response) {
      // Server responded with error status
      const { status, data } = error.response;
      
      // Handle 401 Unauthorized - token expired or invalid
      if (status === 401) {
        console.error('Authentication failed - clearing token');
        await tokenManager.deleteToken();
        // Note: Auth context will detect this and redirect to login
      }
      
      // Log other server errors
      console.error(`API Error ${status}:`, data?.detail || data?.message || 'Unknown error');
    } else if (error.request) {
      // Request made but no response received
      console.error('Network error - no response from server');
    } else {
      // Something else happened
      console.error('Request setup error:', error.message);
    }
    
    return Promise.reject(error);
  }
);

