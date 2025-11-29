/**
 * Chat Input Component
 * Message input with camera button for pantry scanning
 */

import React from 'react';
import { View, TextInput, TouchableOpacity, Text, StyleSheet, Keyboard } from 'react-native';
import { colors } from '../../theme';
import { spacing } from '../../theme';
import { CHAT_CONSTANTS } from '../../utils/constants';

interface ChatInputProps {
	value: string;
	onChangeText: (text: string) => void;
	onSend: () => void;
	onCameraPress?: () => void;
	placeholder?: string;
	disabled?: boolean;
	renderRightButton?: () => React.ReactNode;
}

export default function ChatInput({
	value,
	onChangeText,
	onSend,
	onCameraPress,
	placeholder = CHAT_CONSTANTS.placeholders.input,
	disabled = false,
	renderRightButton,
}: ChatInputProps) {
	// Handle send button press
	const handleSend = () => {
		if (value.trim() && !disabled) {
			Keyboard.dismiss();
			onSend();
		}
	};

	return (
		<View style={styles.container}>
			{/* Camera button */}
			{onCameraPress && (
				<TouchableOpacity 
					style={styles.cameraButton}
					onPress={() => {
						Keyboard.dismiss();
						onCameraPress();
					}}
					disabled={disabled}
					activeOpacity={0.7}
				>
					<Text style={styles.cameraIcon}>📷</Text>
				</TouchableOpacity>
			)}
			
			{/* Text input with send button inside */}
			<View style={[
				styles.inputContainer,
				renderRightButton && styles.inputContainerWithButton
			]}>
				<TextInput
					style={styles.input}
					value={value}
					onChangeText={onChangeText}
					placeholder={placeholder}
					placeholderTextColor={colors.text.muted}
					multiline
					maxLength={500}
					editable={!disabled}
					returnKeyType="send"
					onSubmitEditing={handleSend}
				/>
				
				{/* Send button inside input */}
				<TouchableOpacity 
					style={[
						styles.sendButton,
						(!value.trim() || disabled) && styles.sendButtonDisabled
					]}
					onPress={handleSend}
					disabled={!value.trim() || disabled}
					activeOpacity={0.7}
				>
					<Text style={styles.sendIcon}>→</Text>
				</TouchableOpacity>
			</View>
			
			{/* Right button (e.g., meal recommendation FAB) */}
			{renderRightButton && renderRightButton()}
		</View>
	);
}

const styles = StyleSheet.create({
	container: {
		flexDirection: 'row',
		alignItems: 'flex-end',
		paddingHorizontal: spacing.md,
		paddingTop: spacing.md,
		backgroundColor: colors.background.primary,
		borderTopWidth: 1,
		borderTopColor: colors.border.light,
	},
	cameraButton: {
		width: 44,
		height: 44,
		borderRadius: 22,
		backgroundColor: colors.primary.light,
		justifyContent: 'center',
		alignItems: 'center',
		marginRight: spacing.xs,
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
	cameraIcon: {
		fontSize: 30,
	},
	inputContainer: {
		flex: 1,
		flexDirection: 'row',
		alignItems: 'flex-end',
		backgroundColor: colors.primary.light,
		borderRadius: 20,
		paddingRight: spacing.xs,
		paddingBottom: spacing.xs,
	},
	inputContainerWithButton: {
		marginRight: spacing.sm,
	},
	input: {
		flex: 1,
		minHeight: 44,
		maxHeight: 100,
		paddingHorizontal: spacing.md,
		paddingTop: spacing.md,
		paddingBottom: spacing.md,
		backgroundColor: 'transparent',
		borderRadius: 20,
		color: colors.text.primary,
		fontSize: 16,
		lineHeight: 20,
	},
	sendButton: {
		width: 36,
		height: 36,
		borderRadius: 18,
		backgroundColor: colors.accent.coral,
		justifyContent: 'center',
		alignItems: 'center',
		marginLeft: spacing.xs,
		marginBottom: spacing.xs,
	},
	sendButtonDisabled: {
		backgroundColor: colors.primary.light,
		opacity: 0.5,
	},
	sendIcon: {
		fontSize: 20,
		color: colors.text.primary,
	},
});