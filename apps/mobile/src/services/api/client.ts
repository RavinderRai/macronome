/**
 * API Client
 * Axios instance configured with base URL and auth interceptors
 */
import axios, { AxiosError, InternalAxiosRequestConfig } from 'axios';
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

// Store reference to get fresh token from Clerk
let getClerkToken: (() => Promise<string | null>) | null = null;

/**
 * Register a function to get fresh Clerk tokens for automatic refresh
 */
export function setClerkTokenGetter(fn: () => Promise<string | null>) {
  getClerkToken = fn;
}

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

// Response interceptor - handle common errors and token refresh
apiClient.interceptors.response.use(
  (response) => response,
  async (error: AxiosError) => {
    const originalRequest = error.config as InternalAxiosRequestConfig & { _retry?: boolean };
    
    if (error.response) {
      // Server responded with error status
      const { status, data } = error.response;
      
      // Handle 401 Unauthorized - try to refresh token
      if (status === 401 && originalRequest && !originalRequest._retry) {
        originalRequest._retry = true;
        
        console.log('🔄 Token expired, attempting to refresh...');
        
        try {
          // Try to get fresh token from Clerk
          if (getClerkToken) {
            const newToken = await getClerkToken();
            
            if (newToken) {
              console.log('✅ Got fresh token, retrying request...');
              // Update token in storage
              await tokenManager.saveToken(newToken);
              // Update authorization header
              originalRequest.headers.Authorization = `Bearer ${newToken}`;
              // Retry the original request
              return apiClient(originalRequest);
            }
          }
        } catch (refreshError) {
          console.error('Failed to refresh token:', refreshError);
        }
        
        // If refresh failed, clear token and let error propagate
        console.error('Authentication failed - clearing token');
        await tokenManager.deleteToken();
        // Note: Auth context will detect this and redirect to login
      }
      
      // Log other server errors
      const errorData = data as any;
      console.error(`API Error ${status}:`, errorData?.detail || errorData?.message || 'Unknown error');
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

