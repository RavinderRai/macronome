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
	Platform 
} from 'react-native';
import { colors } from '../theme';
import { spacing } from '../theme';
import { CHAT_CONSTANTS } from '../utils/constants';

// Import stores
import { useChatStore, usePantryStore } from '../store';

// Import components
import Header from '../components/common/Header';
import EmptyState from '../components/common/EmptyState';
import LoadingSpinner from '../components/common/LoadingSpinner';
import FilterSection from '../components/filters/FilterSection';
import ChatMessage from '../components/chat/ChatMessage';
import ChatInput from '../components/chat/ChatInput';
import PantryDrawer from '../components/pantry/PantryDrawer';
import CameraScreen from './CameraScreen';

export default function HomeScreen() {
	// Local state for input text
	const [inputText, setInputText] = useState('');
	const [cameraVisible, setCameraVisible] = useState(false);
	
	// Ref for scrolling to bottom
	const flatListRef = useRef<FlatList>(null);

  // Get state and actions from Zustand stores
  const messages = useChatStore((state) => state.messages);
  const isLoading = useChatStore((state) => state.isLoading);
  const addMessage = useChatStore((state) => state.addMessage);
	const addItems = usePantryStore((state) => state.addItems);

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
  const handleSend = () => {
    if (inputText.trim()) {
      // Add user message to store
      addMessage({
        text: inputText,
        type: 'user',
      });

      // Clear input text
      setInputText('');

      // TODO: Call API to get response (placeholder for now)
      // For now, add a mock response
      setTimeout(() => {
        addMessage({
          text: 'This is a mock response. In a real app, you would call the API here.',
          type: 'assistant',
        });
      }, 1000);

      // Scroll to bottom
      setTimeout(() => {
        flatListRef.current?.scrollToEnd({ animated: true });
      }, 100);
    }
  };

  // Handle camera button press
  const handleCameraPress = () => {
    setCameraVisible(true);
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