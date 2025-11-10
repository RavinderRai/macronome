/**
 * Camera Service
 * Handles camera permissions and image processing
 */

import { CameraView } from 'expo-camera';
import * as ImagePicker from 'expo-image-picker';

export interface CameraPermissionStatus {
	granted: boolean;
	canAskAgain: boolean;
}

export interface ProcessedImage {
    uri: string;
    width: number;
    height: number;
    base64: string;
}

/**
 * Request camera permissions
 * Note: For expo-camera v17+, permissions should be requested using the useCameraPermissions hook
 * This function is kept for compatibility but delegates to ImagePicker for now
 */
export async function requestCameraPermissions(): Promise<CameraPermissionStatus> {
	try {
		// Use ImagePicker permissions API which works similarly
		const { status, canAskAgain } = await ImagePicker.requestCameraPermissionsAsync();
		return {
			granted: status === 'granted',
			canAskAgain: canAskAgain ?? true,
		};
	} catch (error) {
		console.error('Error requesting camera permissions:', error);
		return {
			granted: false,
			canAskAgain: false,
		};
	}
}

/**
 * Check if camera permissions are already granted
 */
export async function checkCameraPermissions(): Promise<boolean> {
	try {
		const { status } = await ImagePicker.getCameraPermissionsAsync();
		return status === 'granted';
	} catch (error) {
		console.error('Error checking camera permissions:', error);
		return false;
	}
}

/**
 * Request image picker permissions (for selecting from gallery)
 */
export async function requestImagePickerPermissions(): Promise<CameraPermissionStatus> {
	try {
		const { status, canAskAgain } = await ImagePicker.requestMediaLibraryPermissionsAsync();
		return {
			granted: status === 'granted',
			canAskAgain,
		};
	} catch (error) {
		console.error('Error requesting image picker permissions:', error);
		return {
			granted: false,
			canAskAgain: false,
		};
	}
}

/**
 * Process image for ML pipeline
 * Converts image to format expected by backend
 */
export async function processImageForML(imageUri: string, base64?: string): Promise<ProcessedImage> {
	// TODO: Add image preprocessing if needed (resize, compress, etc.)
	// For now, return basic info
	return {
		uri: imageUri,
		width: 0, // Will be filled by backend
		height: 0,
        base64: base64 || '',
	};
}

/**
 * Send image to ML backend for pantry item detection
 * TODO: Replace with actual API call to your FastAPI backend
 */
export async function detectPantryItems(imageUri: string, base64?: string): Promise<any[]> {
    try {
        console.log('Sending image to ML backend for pantry item detection...', imageUri);

		// TODO: Implement actual API call to your FastAPI backend
		// Example structure:
		// const response = await fetch('YOUR_BACKEND_URL/api/pantry/detect', {
		//   method: 'POST',
		//   headers: {
		//     'Content-Type': 'application/json',
		//   },
		//   body: JSON.stringify({
		//     image: base64,  // Send base64 encoded image
		//     // Or use FormData for multipart upload:
		//     // image_uri: imageUri,
		//   }),
		// });
		//
		// const data = await response.json();
		// 
		// Expected response format from your ML pipeline:
		// {
		//   "items": [
		//     {
		//       "name": "Eggs",
		//       "category": "Protein",
		//       "confidence": 0.95,
		//       "bounding_box": { "x": 100, "y": 200, "width": 50, "height": 60 }
		//     }
		//   ]
		// }
		//
		// return data.items.map(item => ({
		//   name: item.name,
		//   category: item.category,
		//   confidence: item.confidence,
		//   confirmed: false,
		//   boundingBox: item.bounding_box,
		// }));

		// Mock response for now (simulates ML detection results)
		console.log('📊 Base64 length:', base64?.length || 0);
		
		return new Promise((resolve) => {
			setTimeout(() => {
				resolve([
					{
						name: 'Apple',
						category: 'Fruits',
						confidence: 0.92,
						confirmed: false,
					},
					{
						name: 'Orange Juice',
						category: 'Beverages',
						confidence: 0.87,
						confirmed: false,
					},
					{
						name: 'Yogurt',
						category: 'Dairy',
						confidence: 0.95,
						confirmed: false,
					},
				]);
			}, 2000); // Simulate network delay
		});
	} catch (error) {
		console.error('Error detecting pantry items:', error);
		throw error;
	}
}

/**
 * Pick image from gallery with base64 encoding
 */
export async function pickImageFromGallery(): Promise<{ uri: string; base64?: string } | null> {
	try {
		const result = await ImagePicker.launchImageLibraryAsync({
			mediaTypes: ImagePicker.MediaTypeOptions.Images,
			allowsEditing: true,
			quality: 0.8,
			base64: true, // Enable base64 encoding
		});

		if (!result.canceled && result.assets[0]) {
			return {
				uri: result.assets[0].uri,
				base64: result.assets[0].base64 || undefined,
			};
		}

		return null;
	} catch (error) {
		console.error('Error picking image from gallery:', error);
		return null;
	}
}