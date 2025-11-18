/**
 * HomeScreen
 * Main chat interface screen
 */

import React, { useState, useRef } from 'react';
import { 
	View, 
	StyleSheet, 
	FlatList, 
	KeyboardAvoidingView, 
	Platform,
	Alert,
	Modal,
	TouchableOpacity,
	Text
} from 'react-native';
import { colors } from '../theme';
import { spacing } from '../theme';
import { CHAT_CONSTANTS, APP_CONFIG } from '../utils/constants';
import { useAuthContext } from '../contexts/AuthContext';

// Import stores
import { useChatStore, usePantryStore, useUIStore, useFilterStore } from '../store';

// Import API services
import { sendChatMessage, ChatMessageRequest } from '../services/api';

// Import components
import Header from '../components/common/Header';
import EmptyState from '../components/common/EmptyState';
import LoadingSpinner from '../components/common/LoadingSpinner';
import FilterSection from '../components/filters/FilterSection';
import ChatMessage from '../components/chat/ChatMessage';
import ChatInput from '../components/chat/ChatInput';
import PantryDrawer from '../components/pantry/PantryDrawer';
import PantryReviewSheet from '../components/pantry/PantryReviewSheet';
import CameraScreen from './CameraScreen';

export default function HomeScreen() {
	// Local state for input text
	const [inputText, setInputText] = useState('');
	const [cameraVisible, setCameraVisible] = useState(false);
	const [detectedItems, setDetectedItems] = useState<any[]>([]);
	const [detectedImageId, setDetectedImageId] = useState<string | undefined>(undefined);
	const [reviewSheetVisible, setReviewSheetVisible] = useState(false);
	const [chatSessionId, setChatSessionId] = useState<string | undefined>(undefined);
	const [settingsModalVisible, setSettingsModalVisible] = useState(false);
	
	// Ref for scrolling to bottom
	const flatListRef = useRef<FlatList>(null);
	
	// Auth context
	const { signOut } = useAuthContext();

  // Get state and actions from Zustand stores
  const messages = useChatStore((state) => state.messages);
  const isLoading = useChatStore((state) => state.isLoading);
  const addMessage = useChatStore((state) => state.addMessage);
  const setLoading = useChatStore((state) => state.setLoading);
	const addItems = usePantryStore((state) => state.addItems);
	const setDrawerOpen = useUIStore((state) => state.setDrawerOpen);
	const setConstraintsFromBackend = useFilterStore((state) => state.setConstraintsFromBackend);


  // Handle sending a message
  const handleSend = async () => {
    if (!inputText.trim()) return;

    const userMessage = inputText.trim();
    
    // Add user message to store immediately
    addMessage({
      text: userMessage,
      type: 'user',
    });

    // Clear input text
    setInputText('');
    
    // Set loading state
    setLoading(true);

    // Scroll to bottom to show user message
    setTimeout(() => {
      flatListRef.current?.scrollToEnd({ animated: true });
    }, 100);

    try {
      // Call chat API
      console.log('💬 Sending message to chat API:', userMessage);
      
      const request: ChatMessageRequest = {
        message: userMessage,
        chat_session_id: chatSessionId,
      };

      const response = await sendChatMessage(request);
      
      console.log('✅ Chat API response:', response);

      // Store chat session ID for future messages
      if (response.chat_session_id) {
        setChatSessionId(response.chat_session_id);
      }

      // Add assistant response to store
      addMessage({
        text: response.response,
        type: 'assistant',
      });

      // Handle meal recommendation if task_id is present
      if (response.task_id) {
        console.log('🍽️ Meal recommendation task queued:', response.task_id);
        // TODO: Implement meal recommendation polling
        // For now, just show a message
        setTimeout(() => {
          addMessage({
            text: `I'm working on a meal recommendation for you! Task ID: ${response.task_id}`,
            type: 'assistant',
          });
        }, 500);
      }

      // Handle constraint updates from chat
      if (response.updated_constraints) {
        console.log('✅ Constraints updated:', response.updated_constraints);
        // Update filter store (backend already saved them, so use setConstraintsFromBackend)
        setConstraintsFromBackend(response.updated_constraints);
      }

      // Scroll to bottom to show assistant response
      setTimeout(() => {
        flatListRef.current?.scrollToEnd({ animated: true });
      }, 100);

    } catch (error: any) {
      console.error('❌ Chat API error:', error);
      
      // Show error message to user
      const errorMessage = error.response?.data?.detail || error.message || 'Failed to send message. Please try again.';
      
      addMessage({
        text: `Error: ${errorMessage}`,
        type: 'assistant',
      });

      Alert.alert(
        'Error',
        errorMessage,
        [{ text: 'OK' }]
      );
    } finally {
      setLoading(false);
    }
  };

  // Handle camera button press
  const handleCameraPress = () => {
    setCameraVisible(true);
  };

	// Handle detected items from camera
	const handleItemsDetected = (result: { items: any[]; image_id?: string }) => {
		console.log('🏠 HomeScreen received items:', result.items.length);
		if (result.image_id) {
			console.log('🏠 HomeScreen received image_id:', result.image_id);
		}
		setDetectedItems(result.items);
		setDetectedImageId(result.image_id);
		setReviewSheetVisible(true);
		console.log('🏠 Review sheet should be visible now');
	};

	// Handle review confirmation
	const handleReviewConfirm = async (confirmedItems: any[]) => {
		try {
			// Add items with image_id if available (addItems will sync to backend)
			await addItems(confirmedItems, detectedImageId);
		setReviewSheetVisible(false);
		setDetectedItems([]);
			setDetectedImageId(undefined);
		
		// Open pantry drawer to show new items
		setTimeout(() => {
			setDrawerOpen(true);
		}, 300);

		// Show success message
		Alert.alert(
			'Items Added',
			`Added ${confirmedItems.length} ${confirmedItems.length === 1 ? 'item' : 'items'} to your pantry.`,
			[{ text: 'OK' }]
		);
		} catch (error) {
			console.error('Failed to add items:', error);
			Alert.alert(
				'Error',
				'Failed to add items. Please try again.',
				[{ text: 'OK' }]
			);
		}
	};

	// Handle review close
	const handleReviewClose = () => {
		setReviewSheetVisible(false);
		setDetectedItems([]);
		setDetectedImageId(undefined);
	};

  // Handle settings button press
  const handleSettingsPress = () => {
    setSettingsModalVisible(true);
  };

  // Handle logout
  const handleLogout = async () => {
    Alert.alert(
      'Sign Out',
      'Are you sure you want to sign out?',
      [
        { text: 'Cancel', style: 'cancel' },
        {
          text: 'Sign Out',
          style: 'destructive',
          onPress: async () => {
            try {
              await signOut();
              setSettingsModalVisible(false);
            } catch (error) {
              console.error('Logout error:', error);
              Alert.alert('Error', 'Failed to sign out. Please try again.');
            }
          },
        },
      ]
    );
  };

  return (
    <KeyboardAvoidingView
      style={styles.container}
      behavior={Platform.OS ==='ios' ? 'padding' : undefined}
      keyboardVerticalOffset={0}
    >
      {/* Header */}
      <Header
        onSettingsPress={handleSettingsPress}
      />

      {/* Filter Section */}
      <FilterSection />

      {/* Chat Messages Area */}
      <View style={styles.messagesContainer}>
        {messages.length === 0 ? (
          // Empty state when no messages
          <EmptyState
            icon="💬"
            title="Start a conversation"
            message={CHAT_CONSTANTS.placeholders.empty}
          />
        ) : (
          // Messages list
          <FlatList
            ref={flatListRef}
            data={messages}
            keyExtractor={(item) => item.id}
            renderItem={({ item }) => <ChatMessage message={item} />}
            contentContainerStyle={styles.messagesList}
            onContentSizeChange={() => {
              // Auto-scroll to bottom when new messages arrive
              flatListRef.current?.scrollToEnd({ animated: true });
            }}
          />
        )}

        {/* Loading indicator */}
        {isLoading && (
          <View style={styles.loadingContainer}>
            <LoadingSpinner message="Thinking..." />
          </View>
        )}
      </View>

      {/* Chat Input */}
      <ChatInput
        value={inputText}
        onChangeText={setInputText}
        onSend={handleSend}
        onCameraPress={handleCameraPress}
        disabled={isLoading}
      />

      {/* Pantry Drawer - slides in from left */}
      <PantryDrawer onCameraPress={handleCameraPress} />

      {/* Camera Screen - full screen modal */}
      <CameraScreen 
        visible={cameraVisible}
        onClose={() => setCameraVisible(false)}
				onItemsDetected={handleItemsDetected}
      />

			{/* Pantry Review Sheet */}
			<PantryReviewSheet
				items={detectedItems}
				visible={reviewSheetVisible}
				onClose={handleReviewClose}
				onConfirm={handleReviewConfirm}
			/>

			{/* Settings Modal */}
			<Modal
				visible={settingsModalVisible}
				transparent={true}
				animationType="fade"
				onRequestClose={() => setSettingsModalVisible(false)}
			>
				<TouchableOpacity
					style={styles.modalOverlay}
					activeOpacity={1}
					onPress={() => setSettingsModalVisible(false)}
				>
					<View style={styles.modalContent} onStartShouldSetResponder={() => true}>
						<Text style={styles.modalTitle}>{APP_CONFIG.name}</Text>
						<Text style={styles.modalTagline}>{APP_CONFIG.tagline}</Text>
						<Text style={styles.modalVersion}>Version {APP_CONFIG.version}</Text>
						
						<View style={styles.modalDivider} />
						
						<Text style={styles.modalAbout}>
							Your AI-powered nutrition co-pilot. Get personalized meal recommendations 
							that match your cravings, diet, and available ingredients.
						</Text>
						
						<TouchableOpacity
							style={styles.logoutButton}
							onPress={handleLogout}
						>
							<Text style={styles.logoutButtonText}>Sign Out</Text>
						</TouchableOpacity>
						
						<TouchableOpacity
							style={styles.closeButton}
							onPress={() => setSettingsModalVisible(false)}
						>
							<Text style={styles.closeButtonText}>Close</Text>
						</TouchableOpacity>
					</View>
				</TouchableOpacity>
			</Modal>
    </KeyboardAvoidingView>
  );
}

const styles = StyleSheet.create({
  container: {
		flex: 1,                              // Take full screen height
		backgroundColor: colors.background.primary,
	},
	messagesContainer: {
		flex: 1,                              // Expand to fill available space
	},
	messagesList: {
		paddingTop: spacing.md,
		paddingBottom: spacing.md,
	},
	loadingContainer: {
		position: 'absolute',                 // Float above messages
		bottom: spacing.md,
		left: spacing.md,
		right: spacing.md,
	},
	modalOverlay: {
		flex: 1,
		backgroundColor: 'rgba(0, 0, 0, 0.5)',
		justifyContent: 'center',
		alignItems: 'center',
		padding: spacing.lg,
	},
	modalContent: {
		backgroundColor: colors.background.secondary,
		borderRadius: 16,
		padding: spacing.xl,
		width: '100%',
		maxWidth: 400,
		alignItems: 'center',
	},
	modalTitle: {
		fontSize: 28,
		fontWeight: '700',
		color: colors.text.primary,
		marginBottom: spacing.xs,
	},
	modalTagline: {
		fontSize: 14,
		color: colors.text.muted,
		fontStyle: 'italic',
		marginBottom: spacing.sm,
		textAlign: 'center',
	},
	modalVersion: {
		fontSize: 12,
		color: colors.text.muted,
		marginBottom: spacing.md,
	},
	modalDivider: {
		width: '100%',
		height: 1,
		backgroundColor: colors.border.light,
		marginVertical: spacing.md,
	},
	modalAbout: {
		fontSize: 14,
		color: colors.text.secondary,
		textAlign: 'center',
		lineHeight: 20,
		marginBottom: spacing.lg,
	},
	logoutButton: {
		backgroundColor: colors.accent.coral,
		paddingVertical: spacing.md,
		paddingHorizontal: spacing.xl,
		borderRadius: 8,
		width: '100%',
		marginBottom: spacing.sm,
	},
	logoutButtonText: {
		color: colors.text.primary,
		fontSize: 16,
		fontWeight: '600',
		textAlign: 'center',
	},
	closeButton: {
		paddingVertical: spacing.sm,
		paddingHorizontal: spacing.lg,
	},
	closeButtonText: {
		color: colors.text.muted,
		fontSize: 14,
	},
});