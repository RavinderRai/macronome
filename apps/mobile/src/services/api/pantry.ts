/**
 * Pantry API Service
 * Handles pantry scanning and CRUD operations
 */
import { apiClient } from './client';

// Types
export interface DetectedItem {
  name: string;
  category?: string;
  confidence: number;
  bounding_box?: {
    x: number;
    y: number;
    width: number;
    height: number;
  };
}

export interface PantryScanResponse {
  items: DetectedItem[];
  num_items: number;
  image_id?: string; // ID of saved pantry image for linking items
}

export interface PantryItem {
  id: string;
  user_id: string;
  name: string;
  category?: string;
  confirmed: boolean;
  confidence?: number;
  image_id?: string;
  created_at: string;
  updated_at: string;
}

export interface PantryItemsResponse {
  items: PantryItem[];
  total: number;
}

export interface PantryItemCreate {
  name: string;
  category?: string;
  confirmed: boolean;
  confidence?: number;
  image_id?: string; // Link to pantry_images table
}

export interface PantryItemUpdate {
  name?: string;
  category?: string;
  confirmed?: boolean;
  confidence?: number;
  image_id?: string;
}

/**
 * Scan pantry image to detect food items
 * Uses native fetch API for better Android compatibility with file uploads
 * Includes token refresh logic (since we bypass axios interceptors)
 * @param imageUri - The local file URI of the image
 * @param base64Data - Optional base64 encoded image data (fallback for problematic URIs)
 */
export async function scanPantryImage(imageUri: string, base64Data?: string): Promise<PantryScanResponse> {
  console.log('📤 scanPantryImage called');
  console.log('  📍 Image URI:', imageUri);
  console.log('  📍 URI scheme:', imageUri.split(':')[0]);
  console.log('  📍 Base64 provided:', base64Data ? `yes (${base64Data.length} chars)` : 'no');
  
  // Get imports
  const { tokenManager } = await import('../auth/tokenManager');
  const { ENV } = await import('../../utils/env');
  const { getClerkTokenGetter } = await import('./client');
  
  const baseUrl = ENV.apiBaseUrl;
  const url = `${baseUrl}/api/pantry/scan`;
  console.log('  🌐 Full URL:', url);
  
  // Helper to make request with a given token
  const makeRequest = async (authToken: string) => {
    const formData = new FormData();
    const fileObject = {
      uri: imageUri,
      type: 'image/jpeg',
      name: 'pantry-image.jpg',
    };
    formData.append('file', fileObject as any);
    
    return fetch(url, {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${authToken}`,
      },
      body: formData,
    });
  };
  
  // Get auth token
  let token = await tokenManager.getToken();
  if (!token) {
    console.error('  ❌ No auth token available');
    throw new Error('Authentication required');
  }
  console.log('  🔑 Auth token available');
  
  try {
    console.log('  📤 Sending request with native fetch...');
    let response = await makeRequest(token);
    
    console.log('  📥 Response status:', response.status);
    
    // Handle 401 - try token refresh (same logic as axios interceptor)
    if (response.status === 401) {
      console.log('  🔄 Token expired, attempting to refresh...');
      
      const clerkTokenGetter = getClerkTokenGetter();
      if (clerkTokenGetter) {
        const newToken = await clerkTokenGetter();
        if (newToken) {
          console.log('  ✅ Got fresh token, retrying request...');
          await tokenManager.saveToken(newToken);
          
          // Retry with new token
          response = await makeRequest(newToken);
          console.log('  📥 Retry response status:', response.status);
        } else {
          console.error('  ❌ Failed to get fresh token');
          await tokenManager.deleteToken();
          throw new Error('Authentication expired - please sign in again');
        }
      } else {
        console.error('  ❌ Token refresh not available');
        await tokenManager.deleteToken();
        throw new Error('Authentication expired - please sign in again');
      }
    }
    
    if (!response.ok) {
      const errorText = await response.text();
      console.error('  ❌ Error response:', errorText);
      throw new Error(`HTTP ${response.status}: ${errorText}`);
    }
    
    const data = await response.json();
    console.log('  ✅ Success! Items detected:', data.num_items);
    
    return data as PantryScanResponse;
  } catch (error: any) {
    console.error('  ❌ scanPantryImage error:', error.message);
    console.error('  ❌ Error name:', error.name);
    
    if (error.message === 'Network request failed') {
      console.error('  ❌ Network request failed - possible causes:');
      console.error('     - Device cannot reach server');
      console.error('     - SSL/TLS issues');
      console.error('     - File URI not accessible');
    }
    
    throw error;
  }
}

/**
 * Get user's pantry items
 */
export async function getPantryItems(): Promise<PantryItemsResponse> {
  const response = await apiClient.get<PantryItemsResponse>('/api/pantry/items');
  return response.data;
}

/**
 * Add items to pantry
 */
export async function addPantryItems(items: PantryItemCreate[]): Promise<{ message: string; items: PantryItem[] }> {
  const response = await apiClient.post<{ message: string; items: PantryItem[] }>('/api/pantry/items', items);
  return response.data;
}

/**
 * Update pantry item (partial update)
 */
export async function updatePantryItem(
  itemId: string,
  updates: PantryItemUpdate
): Promise<PantryItem> {
  const response = await apiClient.patch<PantryItem>(`/api/pantry/items/${itemId}`, updates);
  return response.data;
}

/**
 * Delete pantry item
 */
export async function deletePantryItem(itemId: string): Promise<void> {
  await apiClient.delete(`/api/pantry/items/${itemId}`);
}
