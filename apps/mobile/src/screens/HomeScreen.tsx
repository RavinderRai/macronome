/**
 * HomeScreen
 * Main chat interface screen
 */

import React, { useState, useRef, useEffect } from 'react';
import { 
	View, 
	StyleSheet, 
	FlatList, 
	KeyboardAvoidingView, 
	Platform,
	Alert,
	Modal,
	TouchableOpacity,
	Text,
	Keyboard
} from 'react-native';
import { colors } from '../theme';
import { spacing } from '../theme';
import { CHAT_CONSTANTS, APP_CONFIG } from '../utils/constants';
import { useAuthContext } from '../contexts/AuthContext';

// Import stores
import { useChatStore, usePantryStore, useUIStore, useFilterStore } from '../store';

// Import API services
import { sendChatMessage, ChatMessageRequest } from '../services/api';
import { recommendMeal, getRecommendationStatus, MealRecommendRequest } from '../services/api/meals';

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
	const [mealLoading, setMealLoading] = useState(false);
	
	// Ref for scrolling to bottom
	const flatListRef = useRef<FlatList>(null);
	const pollTimeoutRef = useRef<NodeJS.Timeout | null>(null);
	
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

	// Cleanup polling timeout on unmount
	useEffect(() => {
		return () => {
			if (pollTimeoutRef.current) {
				clearTimeout(pollTimeoutRef.current);
			}
		};
	}, []);

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
        const taskId = response.task_id; // Store for use in closure
        console.log('🍽️ Meal recommendation task queued:', taskId);
        
        // Show meal loading spinner (same as button)
        setMealLoading(true);
        
        // Poll for status with timeout
        const MAX_POLLS = 210; // 7 minutes max (210 * 2 seconds)
        const POLL_INTERVAL = 2000; // 2 seconds
        let pollCount = 0;

        const pollStatus = async (): Promise<void> => {
          if (pollCount >= MAX_POLLS) {
            console.log('⏱️ Polling timeout reached');
            if (pollTimeoutRef.current) {
              clearTimeout(pollTimeoutRef.current);
              pollTimeoutRef.current = null;
            }
            setMealLoading(false);
            addMessage({
              text: 'Sorry, the meal recommendation is taking longer than expected. Please try again.',
              type: 'assistant',
            });
            return;
          }

          try {
            const status = await getRecommendationStatus(taskId);
            pollCount++;
            console.log(`🔄 Poll ${pollCount}/${MAX_POLLS}: status=${status.status}`);

            if (status.status === 'success' && status.result) {
              // Celery task succeeded, check workflow result
              if (pollTimeoutRef.current) {
                clearTimeout(pollTimeoutRef.current);
                pollTimeoutRef.current = null;
              }
              
              if (status.result.success === true && status.result.recommendation) {
                // Workflow succeeded - use structured component
                setMealLoading(false);
                
                addMessage({
                  text: '', // Empty text, using component instead
                  type: 'assistant',
                  component: 'MealRecommendationCard',
                  data: status.result.recommendation,
                });
                
                // Scroll to bottom
                setTimeout(() => {
                  flatListRef.current?.scrollToEnd({ animated: true });
                }, 100);
                
              } else if (status.result.success === false) {
                // Workflow failed - use error component
                setMealLoading(false);
                
                addMessage({
                  text: '', // Empty text, using component instead
                  type: 'assistant',
                  component: 'ErrorCard',
                  data: {
                    error_message: status.result.error_message || 'Could not generate a meal recommendation.',
                    suggestions: status.result.suggestions || [],
                  },
                });
              } else {
                // Unexpected result structure
                setMealLoading(false);
                addMessage({
                  text: 'Sorry, received an unexpected response. Please try again.',
                  type: 'assistant',
                });
              }
            } else if (status.status === 'failure') {
              // Celery task failed
              if (pollTimeoutRef.current) {
                clearTimeout(pollTimeoutRef.current);
                pollTimeoutRef.current = null;
              }
              setMealLoading(false);
              addMessage({
                text: `Sorry, the meal recommendation task failed. ${status.error || 'Please try again.'}`,
                type: 'assistant',
              });
            } else if (status.status === 'pending' || status.status === 'started') {
              // Continue polling
              pollTimeoutRef.current = setTimeout(pollStatus, POLL_INTERVAL);
            } else {
              // Unexpected status - stop polling
              console.error('Unexpected status:', status.status);
              if (pollTimeoutRef.current) {
                clearTimeout(pollTimeoutRef.current);
                pollTimeoutRef.current = null;
              }
              setMealLoading(false);
              addMessage({
                text: `Unexpected status: ${status.status}. Please try again.`,
                type: 'assistant',
              });
            }
          } catch (error) {
            console.error('Error polling meal status:', error);
            if (pollTimeoutRef.current) {
              clearTimeout(pollTimeoutRef.current);
              pollTimeoutRef.current = null;
            }
            setMealLoading(false);
          addMessage({
              text: 'Sorry, there was an error getting your meal recommendation. Please try again.',
            type: 'assistant',
          });
          }
        };

        // Start polling after a short delay
        pollTimeoutRef.current = setTimeout(pollStatus, POLL_INTERVAL);
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
    Keyboard.dismiss();
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
    Keyboard.dismiss();
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

  // Handle meal recommendation button press
  const handleMealRecommendation = async () => {
    if (isLoading || mealLoading) return;

    Keyboard.dismiss();
    setMealLoading(true);
    
    try {
      // Get current filter constraints from store
      const filterState = useFilterStore.getState();
      const constraints = filterState.constraints;
      
      // Build request - map frontend constraints to backend format
      const request: MealRecommendRequest = {
        user_query: undefined, // Let the workflow decide based on constraints
        constraints: {
          calorie_range: constraints.calories ? [constraints.calories - 200, constraints.calories + 200] : undefined,
          macros: constraints.macros,
          prep_time: constraints.prepTime,
          diet_type: constraints.diet,
          allergies: constraints.allergies,
          meal_type: constraints.mealType,
        },
      };

      console.log('🍽️ Requesting meal recommendation...');
      
      // Request meal recommendation
      const response = await recommendMeal(request);
      
      console.log('✅ Meal recommendation task queued:', response.task_id);

      // Poll for status with timeout
      const MAX_POLLS = 210; // 7 minutes max (210 * 2 seconds)
      const POLL_INTERVAL = 2000; // 2 seconds
      let pollCount = 0;

      const pollStatus = async (): Promise<void> => {
        if (pollCount >= MAX_POLLS) {
          console.log('⏱️ Polling timeout reached');
          if (pollTimeoutRef.current) {
            clearTimeout(pollTimeoutRef.current);
            pollTimeoutRef.current = null;
          }
          setMealLoading(false);
          addMessage({
            text: 'Sorry, the meal recommendation is taking longer than expected. Please try again.',
            type: 'assistant',
          });
          return;
        }

        try {
          const status = await getRecommendationStatus(response.task_id);
          pollCount++;
          console.log(`🔄 Poll ${pollCount}/${MAX_POLLS}: status=${status.status}`);

          if (status.status === 'success' && status.result) {
            // Celery task succeeded, check workflow result
            // Backend returns: { status: "success", result: { success: bool, recommendation: {...} or error_message: ... } }
            if (pollTimeoutRef.current) {
              clearTimeout(pollTimeoutRef.current);
              pollTimeoutRef.current = null;
            }
            
            if (status.result.success === true && status.result.recommendation) {
              // Workflow succeeded - use structured component
              setMealLoading(false);
              
              addMessage({
                text: '', // Empty text, using component instead
                type: 'assistant',
                component: 'MealRecommendationCard',
                data: status.result.recommendation,
              });
              
              // Scroll to bottom
              setTimeout(() => {
                flatListRef.current?.scrollToEnd({ animated: true });
              }, 100);
              
            } else if (status.result.success === false) {
              // Workflow failed - use error component
              setMealLoading(false);
              
              addMessage({
                text: '', // Empty text, using component instead
                type: 'assistant',
                component: 'ErrorCard',
                data: {
                  error_message: status.result.error_message || 'Could not generate a meal recommendation.',
                  suggestions: status.result.suggestions || [],
                },
              });
            } else {
              // Unexpected result structure
              setMealLoading(false);
              addMessage({
                text: 'Sorry, received an unexpected response. Please try again.',
                type: 'assistant',
              });
            }
          } else if (status.status === 'failure') {
            // Celery task failed
            if (pollTimeoutRef.current) {
              clearTimeout(pollTimeoutRef.current);
              pollTimeoutRef.current = null;
            }
            setMealLoading(false);
            addMessage({
              text: `Sorry, the meal recommendation task failed. ${status.error || 'Please try again.'}`,
              type: 'assistant',
            });
          } else if (status.status === 'pending' || status.status === 'started') {
            // Continue polling
            pollTimeoutRef.current = setTimeout(pollStatus, POLL_INTERVAL);
          } else {
            // Unexpected status - stop polling
            console.error('Unexpected status:', status.status);
            if (pollTimeoutRef.current) {
              clearTimeout(pollTimeoutRef.current);
              pollTimeoutRef.current = null;
            }
            setMealLoading(false);
            addMessage({
              text: `Unexpected status: ${status.status}. Please try again.`,
              type: 'assistant',
            });
          }
        } catch (error) {
          console.error('Error polling meal status:', error);
          if (pollTimeoutRef.current) {
            clearTimeout(pollTimeoutRef.current);
            pollTimeoutRef.current = null;
          }
          setMealLoading(false);
          addMessage({
            text: 'Sorry, there was an error getting your meal recommendation. Please try again.',
            type: 'assistant',
          });
        }
      };

      // Start polling after a short delay
      pollTimeoutRef.current = setTimeout(pollStatus, POLL_INTERVAL);

    } catch (error: any) {
      console.error('❌ Meal recommendation error:', error);
      setMealLoading(false);
      
      const errorMessage = error.response?.data?.detail || error.message || 'Failed to request meal recommendation. Please try again.';
      
      addMessage({
        text: `Error: ${errorMessage}`,
        type: 'assistant',
      });

      Alert.alert(
        'Error',
        errorMessage,
        [{ text: 'OK' }]
      );
    }
  };

  return (
    <KeyboardAvoidingView
      style={styles.container}
      behavior='padding'
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
        renderRightButton={() => (
          <TouchableOpacity
            style={styles.fab}
            onPress={handleMealRecommendation}
            disabled={isLoading || mealLoading}
            activeOpacity={0.8}
          >
            <Text style={styles.fabIcon}>🍽️</Text>
          </TouchableOpacity>
        )}
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

			{/* Full-screen loading overlay for meal recommendations */}
			{mealLoading && (
				<Modal
					visible={mealLoading}
					transparent={true}
					animationType="fade"
				>
					<View style={styles.loadingOverlay}>
						<View style={styles.loadingContent}>
							<LoadingSpinner message="Creating your perfect meal..." />
						</View>
					</View>
				</Modal>
			)}

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
	loadingOverlay: {
		flex: 1,
		backgroundColor: 'rgba(0, 0, 0, 0.7)',
		justifyContent: 'center',
		alignItems: 'center',
	},
	loadingContent: {
		backgroundColor: colors.primary.light, // Dark slate instead of white
		borderRadius: 16,
		padding: spacing.xl,
		borderWidth: 1,
		borderColor: colors.border.light, // Subtle border for definition
	},
	closeButtonText: {
		color: colors.text.muted,
		fontSize: 14,
	},
	fab: {
		width: 44,
		height: 44,
		borderRadius: 22,
		backgroundColor: colors.accent.coral,
		justifyContent: 'center',
		alignItems: 'center',
		marginBottom: 0,
		elevation: 2, // Android shadow
		shadowColor: '#000', // iOS shadow
		shadowOffset: {
			width: 0,
			height: 1,
		},
		shadowOpacity: 0.2,
		shadowRadius: 2,
	},
	fabIcon: {
		fontSize: 22,
	},
});