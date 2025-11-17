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
	Alert
} from 'react-native';
import { colors } from '../theme';
import { spacing } from '../theme';
import { CHAT_CONSTANTS } from '../utils/constants';

// Import stores
import { useChatStore, usePantryStore, useUIStore } from '../store';

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
	const [reviewSheetVisible, setReviewSheetVisible] = useState(false);
	const [chatSessionId, setChatSessionId] = useState<string | undefined>(undefined);
	
	// Ref for scrolling to bottom
	const flatListRef = useRef<FlatList>(null);

  // Get state and actions from Zustand stores
  const messages = useChatStore((state) => state.messages);
  const isLoading = useChatStore((state) => state.isLoading);
  const addMessage = useChatStore((state) => state.addMessage);
  const setLoading = useChatStore((state) => state.setLoading);
	const addItems = usePantryStore((state) => state.addItems);
	const setDrawerOpen = useUIStore((state) => state.setDrawerOpen);

  // TODO: Remove this mock data later
	// Add some mock pantry items for testing (remove this later)
	React.useEffect(() => {
		// Only add mock items if pantry is empty
		const currentItems = usePantryStore.getState().items;
		if (currentItems.length === 0) {
			addItems([
				{
					name: 'Eggs',
					category: 'Protein',
					confirmed: true,
					confidence: 0.95,
				},
				{
					name: 'Milk',
					category: 'Dairy',
					confirmed: true,
					confidence: 0.92,
				},
				{
					name: 'Tomatoes',
					category: 'Vegetables',
					confirmed: false,
					confidence: 0.78,
				},
			]);
		}
	}, [addItems]);

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

      // Handle constraint updates
      if (response.updated_constraints) {
        console.log('✅ Constraints updated:', response.updated_constraints);
        // TODO: Update filter store with new constraints
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
	const handleItemsDetected = (items: any[]) => {
		console.log('🏠 HomeScreen received items:', items.length);
		setDetectedItems(items);
		setReviewSheetVisible(true);
		console.log('🏠 Review sheet should be visible now');
	};

	// Handle review confirmation
	const handleReviewConfirm = (confirmedItems: any[]) => {
		addItems(confirmedItems);
		setReviewSheetVisible(false);
		setDetectedItems([]);
		
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
	};

	// Handle review close
	const handleReviewClose = () => {
		setReviewSheetVisible(false);
		setDetectedItems([]);
	};

  // Handle settings button press
  const handleSettingsPress = () => {
    // TODO: Navigate to settings 
    console.log('Settings pressed - will implement later')
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
});