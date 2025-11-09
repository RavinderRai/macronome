/**
 * Chat Input Component
 * Message input with camera button for pantry scanning
 */

import React from 'react';
import { View, TextInput, TouchableOpacity, Text, StyleSheet } from 'react-native';
import { colors } from '../../theme';
import { typography } from '../../theme';
import { spacing } from '../../theme';
import { CHAT_CONSTANTS } from '../../utils/constants';

interface ChatInputProps {
	value: string;
	onChangeText: (text: string) => void;
	onSend: () => void;
	onCameraPress?: () => void;
	placeholder?: string;
	disabled?: boolean;
}

export default function ChatInput({
	value,
	onChangeText,
	onSend,
	onCameraPress,
	placeholder = CHAT_CONSTANTS.placeholders.input,
	disabled = false,
}: ChatInputProps) {
	// Handle send button press
	const handleSend = () => {
		if (value.trim() && !disabled) {
			onSend();
		}
	};

	return (
		<View style={styles.container}>
			{/* Camera button */}
			{onCameraPress && (
				<TouchableOpacity 
					style={styles.cameraButton}
					onPress={onCameraPress}
					disabled={disabled}
					activeOpacity={0.7}
				>
					<Text style={styles.cameraIcon}>📷</Text>
				</TouchableOpacity>
			)}
			
			{/* Text input */}
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
			
			{/* Send button */}
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
	);
}

const styles = StyleSheet.create({
	container: {
		flexDirection: 'row',
		alignItems: 'flex-end',
		paddingHorizontal: spacing.md,
		paddingVertical: spacing.sm,
		backgroundColor: colors.background.primary,
		borderTopWidth: 1,
		borderTopColor: colors.border.light,
	},
	cameraButton: {
		padding: spacing.sm,
		marginRight: spacing.xs,
		marginBottom: spacing.xs,
	},
	cameraIcon: {
		fontSize: 24,
	},
	input: {
		flex: 1,
		minHeight: 44,
		maxHeight: 100,
		paddingHorizontal: spacing.md,
		paddingTop: spacing.md,
		paddingBottom: spacing.md,
		backgroundColor: colors.primary.light,
		borderRadius: 20,
		color: colors.text.primary,
		fontSize: 16,
		lineHeight: 20,
	},
	sendButton: {
		width: 40,
		height: 40,
		borderRadius: 20,
		backgroundColor: colors.accent.coral,
		justifyContent: 'center',
		alignItems: 'center',
		marginLeft: spacing.sm,
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