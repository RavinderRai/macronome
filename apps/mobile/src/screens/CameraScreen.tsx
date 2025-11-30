/**
 * Camera Screen
 * Full-screen camera for scanning pantry items
 */

import React, { useState, useRef } from 'react';
import {
	View,
	Text,
	TouchableOpacity,
	StyleSheet,
	Alert,
	ActivityIndicator,
	Modal,
	Image,
} from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { CameraView, useCameraPermissions } from 'expo-camera';
import * as Linking from 'expo-linking';
import { colors, spacing } from '../theme';
import { usePantryStore, useUIStore } from '../store';
import {
	detectPantryItems,
	pickImageFromGallery,
	requestImagePickerPermissions,
	checkImagePickerPermissions,
} from '../services/camera/cameraService';
interface CameraScreenProps {
	visible: boolean;
	onClose: () => void;
	onItemsDetected: (result: { items: any[]; image_id?: string }) => void;
}

export default function CameraScreen({ visible, onClose, onItemsDetected }: CameraScreenProps) {
	const [permission, requestPermission] = useCameraPermissions();
	const [isProcessing, setIsProcessing] = useState(false);
	const [cameraFacing, setCameraFacing] = useState<'front' | 'back'>('back');
	
	const cameraRef = useRef<CameraView>(null);
	const setLoading = usePantryStore((state) => state.setLoading);

	// Request permissions when modal opens
	React.useEffect(() => {
		if (visible && !permission?.granted) {
			requestPermission();
		}
	}, [visible]);

	const takePicture = async () => {
		if (!cameraRef.current || isProcessing) return;

		try {
			setIsProcessing(true);

			// Capture photo WITH base64 encoding
			const photo = await cameraRef.current.takePictureAsync({
				quality: 0.8,
				base64: true, // CHANGED: Enable base64 encoding for ML pipeline
			});

			console.log('📸 Photo captured:', photo.uri);
			console.log('📊 Base64 length:', photo.base64?.length || 0);

			// Show loading state
			setLoading(true);

			// Send to ML pipeline with base64
			console.log('🔍 Detecting pantry items...');
			const scanResult = await detectPantryItems(photo.uri, photo.base64);
			console.log('✅ Detection complete. Items found:', scanResult.items.length);
			console.log('📦 Items:', scanResult.items);
			if (scanResult.image_id) {
				console.log('🖼️ Image ID:', scanResult.image_id);
			}
				
			// Pass items and image_id to parent to show review sheet
			if (scanResult.items.length > 0) {
				console.log('🎯 Showing review sheet with', scanResult.items.length, 'items');
				onClose(); // Close camera first
				setTimeout(() => {
					onItemsDetected({ items: scanResult.items, image_id: scanResult.image_id }); // Show review sheet after camera closes
				}, 300);
			} else {
				Alert.alert(
					'No Items Detected',
					'Try taking another photo with better lighting.',
					[{ text: 'OK' }]
				);
			}
		} catch (error) {
			console.error('Error taking picture:', error);
			Alert.alert(
				'Error',
				'Failed to process image. Please try again.',
				[{ text: 'OK' }]
			);
		} finally {
			setIsProcessing(false);
			setLoading(false);
		}
	};

	const processGalleryImage = async () => {
		try {
			setIsProcessing(true);
			const result = await pickImageFromGallery();

			if (result && result.uri) {
				console.log('🖼️ Image selected:', result.uri);
				console.log('📊 Base64 length:', result.base64?.length || 0);
				
				setLoading(true);
				const scanResult = await detectPantryItems(result.uri, result.base64);

				if (scanResult.items.length > 0) {
					onClose(); // Close camera first
					onItemsDetected({ items: scanResult.items, image_id: scanResult.image_id }); // Show review sheet
				} else {
					Alert.alert(
						'No Items Detected',
						'Try selecting another photo.',
						[{ text: 'OK' }]
					);
				}
				setLoading(false);
			}
		} catch (error) {
			console.error('Error processing gallery image:', error);
			Alert.alert(
				'Error',
				'Failed to process image. Please try again.',
				[{ text: 'OK' }]
			);
		} finally {
			setIsProcessing(false);
			setLoading(false);
		}
	};

	const handlePickFromGallery = async () => {
		try {
			// Check current permission status first
			let permissionStatus = await checkImagePickerPermissions();
			
			// If not granted, request permissions
			if (!permissionStatus.granted) {
				permissionStatus = await requestImagePickerPermissions();
			}
			
			// If still not granted, show dialog with options
			if (!permissionStatus.granted) {
				const canAskAgain = permissionStatus.canAskAgain;
				
				Alert.alert(
					'Photo Library Access Required',
					'Macronome needs access to your photo library to scan pantry items from your photos.',
					[
						{ text: 'Cancel', style: 'cancel' },
						...(canAskAgain
							? [
									{
										text: 'Grant Permission',
										onPress: async () => {
											// Try requesting again
											const retryStatus = await requestImagePickerPermissions();
											if (retryStatus.granted) {
												// Permission granted, proceed with gallery picker
												await processGalleryImage();
											}
										},
									},
							  ]
							: [
									{
										text: 'Open Settings',
										onPress: () => {
											Linking.openSettings();
										},
									},
							  ]),
					]
				);
				return;
			}

			// Permission granted, proceed with gallery picker
			await processGalleryImage();
		} catch (error) {
			console.error('Error picking from gallery:', error);
			Alert.alert('Error', 'Failed to process image. Please try again.');
		} finally {
			setIsProcessing(false);
			setLoading(false);
		}
	};

	const toggleCameraType = () => {
		setCameraFacing((current) =>
			current === 'back' ? 'front' : 'back'
		);
	};

	if (!visible) return null;

	// Check permission status
	if (!permission) {
		// Still loading permissions
		return (
			<Modal visible={visible} animationType="slide" presentationStyle="fullScreen">
				<View style={styles.modalBackground}>
					<SafeAreaView style={styles.container}>
					<View style={styles.centered}>
						<ActivityIndicator size="large" color={colors.accent.coral} />
						<Text style={styles.loadingText}>Loading camera...</Text>
					</View>
					</SafeAreaView>
				</View>
			</Modal>
		);
	}

	if (!permission.granted) {
		// No permission yet
		return (
			<Modal visible={visible} animationType="slide" presentationStyle="fullScreen" onRequestClose={onClose}>
				<View style={styles.modalBackground}>
					<SafeAreaView style={styles.container}>
					<View style={styles.centered}>
						<Text style={styles.permissionText}>📷</Text>
						<Text style={styles.permissionTitle}>Camera Access Required</Text>
						<Text style={styles.permissionMessage}>
							Macronome needs camera access to scan your pantry items.
						</Text>
						<TouchableOpacity style={styles.retryButton} onPress={requestPermission}>
							<Text style={styles.retryButtonText}>Grant Permission</Text>
						</TouchableOpacity>
						<TouchableOpacity style={styles.closeButton} onPress={onClose}>
							<Text style={styles.closeButtonText}>Cancel</Text>
						</TouchableOpacity>
					</View>
					</SafeAreaView>
				</View>
			</Modal>
		);
	}

	return (
		<Modal
			visible={visible}
			animationType="slide"
			presentationStyle="fullScreen"
			onRequestClose={onClose}
		>
			<View style={styles.modalBackground}>
				<SafeAreaView style={styles.container}>
					<View style={styles.cameraWrapper}>
						<CameraView
							ref={cameraRef}
							style={styles.camera}
							facing={cameraFacing}
						>
							{/* Header */}
							<View style={styles.header}>
								<TouchableOpacity
									style={styles.headerButton}
									onPress={onClose}
									disabled={isProcessing}
								>
									<Text style={styles.headerButtonText}>✕</Text>
								</TouchableOpacity>
								<Text style={styles.headerTitle}>Scan Pantry</Text>
								<TouchableOpacity
									style={styles.headerButton}
									onPress={toggleCameraType}
									disabled={isProcessing}
								>
									<Text style={styles.headerButtonText}>🔄</Text>
								</TouchableOpacity>
							</View>

							{/* Scanning guide overlay */}
							<View style={styles.overlay}>
								<View style={styles.guideBox} />
								<Text style={styles.guideText}>
									Position your fridge or pantry in frame
								</Text>
							</View>

							{/* Bottom controls */}
							<View style={styles.controls}>
								{/* Gallery button */}
								<TouchableOpacity
									style={styles.galleryButton}
									onPress={handlePickFromGallery}
									disabled={isProcessing}
									activeOpacity={0.7}
								>
									<Image
										source={require('../../assets/gallery-icon.png')}
										style={styles.galleryIcon}
										resizeMode="contain"
										onError={(error) => {
											console.error('Gallery icon load error:', error);
										}}
									/>
								</TouchableOpacity>

								{/* Capture button */}
								<TouchableOpacity
									style={[
										styles.captureButton,
										isProcessing && styles.captureButtonDisabled,
									]}
									onPress={takePicture}
									disabled={isProcessing}
								>
									{isProcessing ? (
										<ActivityIndicator color={colors.text.primary} />
									) : (
										<View style={styles.captureButtonInner} />
									)}
								</TouchableOpacity>

								{/* Placeholder for symmetry */}
								<View style={styles.galleryButton} />
							</View>
						</CameraView>
					</View>

					{/* Processing overlay */}
					{isProcessing && (
						<View style={styles.processingOverlay}>
							<ActivityIndicator size="large" color={colors.accent.coral} />
							<Text style={styles.processingText}>
								Processing image...
							</Text>
						</View>
					)}
				</SafeAreaView>
			</View>
		</Modal>
	);
}

const styles = StyleSheet.create({
	modalBackground: {
		flex: 1,
		backgroundColor: colors.background.primary,
	},
	container: {
		flex: 1,
		backgroundColor: colors.background.primary,
	},
	cameraWrapper: {
		flex: 1,
		backgroundColor: colors.background.primary,
	},
	centered: {
		flex: 1,
		alignItems: 'center',
		justifyContent: 'center',
		padding: spacing.xl,
	},
	loadingText: {
		fontSize: 16,
		lineHeight: 24,
		color: colors.text.secondary,
		marginTop: spacing.md,
	},
	permissionText: {
		fontSize: 64,
		marginBottom: spacing.lg,
	},
	permissionTitle: {
		fontSize: 24,
		fontWeight: '700',
		lineHeight: 32,
		color: colors.text.primary,
		marginBottom: spacing.sm,
		textAlign: 'center',
	},
	permissionMessage: {
		fontSize: 16,
		lineHeight: 24,
		color: colors.text.secondary,
		textAlign: 'center',
		marginBottom: spacing.xl,
	},
	retryButton: {
		backgroundColor: colors.accent.coral,
		paddingHorizontal: spacing.xl,
		paddingVertical: spacing.md,
		borderRadius: 8,
		marginBottom: spacing.md,
	},
	retryButtonText: {
		fontSize: 16,
		fontWeight: '600',
		lineHeight: 24,
		color: colors.text.primary,
	},
	closeButton: {
		paddingHorizontal: spacing.xl,
		paddingVertical: spacing.md,
	},
	closeButtonText: {
		fontSize: 16,
		lineHeight: 24,
		color: colors.text.secondary,
	},
	camera: {
		flex: 1,
		backgroundColor: colors.background.primary,
	},
	header: {
		flexDirection: 'row',
		alignItems: 'center',
		justifyContent: 'space-between',
		paddingHorizontal: spacing.md,
		paddingVertical: spacing.lg,
		backgroundColor: 'rgba(30, 41, 59, 0.95)', // More solid dark blue background
	},
	headerButton: {
		width: 44,
		height: 44,
		alignItems: 'center',
		justifyContent: 'center',
	},
	headerButtonText: {
		fontSize: 24,
		color: '#FFFFFF', // Pure white for better visibility
		fontWeight: '700', // Bolder
		textShadowColor: 'rgba(0, 0, 0, 0.5)',
		textShadowOffset: { width: 0, height: 1 },
		textShadowRadius: 2,
	},
	headerTitle: {
		fontSize: 18,
		fontWeight: '700', // Bolder
		lineHeight: 24,
		color: '#FFFFFF', // Pure white for better visibility
		textShadowColor: 'rgba(0, 0, 0, 0.5)',
		textShadowOffset: { width: 0, height: 1 },
		textShadowRadius: 2,
	},
	overlay: {
		flex: 1,
		alignItems: 'center',
		justifyContent: 'center',
		backgroundColor: 'transparent', // Transparent so camera feed shows through
	},
	guideBox: {
		width: '80%',
		height: '60%',
		borderWidth: 2,
		borderColor: colors.accent.coral,
		borderRadius: 16,
		backgroundColor: 'transparent',
	},
	guideText: {
		fontSize: 16,
		lineHeight: 24,
		color: colors.text.inverse,
		marginTop: spacing.lg,
		textAlign: 'center',
		backgroundColor: 'rgba(0, 0, 0, 0.6)',
		paddingHorizontal: spacing.lg,
		paddingVertical: spacing.sm,
		borderRadius: 8,
	},
	controls: {
		flexDirection: 'row',
		alignItems: 'center',
		justifyContent: 'space-between',
		paddingHorizontal: spacing.xl,
		paddingVertical: spacing.xl,
		backgroundColor: 'rgba(30, 41, 59, 0.8)', // Dark blue with transparency
	},
	galleryButton: {
		width: 60,
		height: 60,
		alignItems: 'center',
		justifyContent: 'center',
		// backgroundColor: 'rgba(255, 0, 0, 0.3)', // Debug: uncomment to see button area
	},
	galleryIcon: {
		width: 40,
		height: 40,
		// tintColor removed - use original image colors
		opacity: 0.9, // Adjust this value (0.0 to 1.0) to control translucency
	},
	captureButton: {
		width: 80,
		height: 80,
		borderRadius: 40,
		backgroundColor: colors.text.inverse,
		alignItems: 'center',
		justifyContent: 'center',
		borderWidth: 4,
		borderColor: colors.accent.coral,
	},
	captureButtonDisabled: {
		opacity: 0.5,
	},
	captureButtonInner: {
		width: 64,
		height: 64,
		borderRadius: 32,
		backgroundColor: colors.accent.coral,
	},
	processingOverlay: {
		...StyleSheet.absoluteFillObject,
		backgroundColor: 'rgba(0, 0, 0, 0.8)',
		alignItems: 'center',
		justifyContent: 'center',
	},
	processingText: {
		fontSize: 18,
		lineHeight: 24,
		color: colors.text.inverse,
		marginTop: spacing.md,
	},
});