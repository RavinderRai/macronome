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
  image_id?: string;
}

/**
 * Scan pantry image to detect food items
 */
export async function scanPantryImage(imageUri: string): Promise<PantryScanResponse> {
  // Convert image URI to FormData
  const formData = new FormData();
  
  // For React Native, we need to create a file object
  // The imageUri should be a local file path
  formData.append('file', {
    uri: imageUri,
    type: 'image/jpeg',
    name: 'pantry-image.jpg',
  } as any);

  const response = await apiClient.post<PantryScanResponse>('/api/pantry/scan', formData, {
    headers: {
      'Content-Type': 'multipart/form-data',
    },
  });

  return response.data;
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
 * Delete pantry item
 */
export async function deletePantryItem(itemId: string): Promise<void> {
  await apiClient.delete(`/api/pantry/items/${itemId}`);
}
