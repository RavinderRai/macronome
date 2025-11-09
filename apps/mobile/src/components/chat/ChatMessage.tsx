/**
 * Chat Message Component
 * Individual message bubble with sender and timestamp
 */

import React from 'react';
import { View, Text, StyleSheet } from 'react-native';
import { colors } from '../../theme';
import { typography } from '../../theme';
import { spacing } from '../../theme';
import type { Message } from '../../types/chat';

interface ChatMessageProps {
    message: Message;
}

export default function ChatMessage({ message }: ChatMessageProps) {
    // Determine if this is a user message
    const isUser = message.type === 'user';

    // Format timestamp to show time only (e.g., "10:30 AM")
    const formatTime = (date: Date) => {
        return new Date(date).toLocaleTimeString('en-US', {
            hour: 'numeric',
            minute: '2-digit',
        });
    };

	return (
		<View style={[
			styles.container,
			isUser ? styles.userContainer : styles.assistantContainer
		]}>
			{/* Message bubble */}
			<View style={[
				styles.bubble,
				isUser ? styles.userBubble : styles.assistantBubble
			]}>
				<Text style={[
					styles.text,
					isUser ? styles.userText : styles.assistantText
				]}>
					{message.text}
				</Text>
				
				{/* Timestamp */}
				<Text style={[
					styles.timestamp,
					isUser ? styles.userTimestamp : styles.assistantTimestamp
				]}>
					{formatTime(message.timestamp)}
				</Text>
			</View>
		</View>
	);
}

const styles = StyleSheet.create({
	container: {
		marginBottom: spacing.md,
		paddingHorizontal: spacing.md,
	},
	// User messages aligned to the right
	userContainer: {
		alignItems: 'flex-end',
	},
	// Assistant messages aligned to the left
	assistantContainer: {
		alignItems: 'flex-start',
	},
	bubble: {
		maxWidth: '80%',                    // Don't stretch full width
		paddingVertical: spacing.md,
		paddingHorizontal: spacing.md,
		borderRadius: 16,
	},
	userBubble: {
		backgroundColor: colors.accent.coral,
		borderBottomRightRadius: 4,        // Sharp corner on user side
	},
	assistantBubble: {
		backgroundColor: colors.primary.light,
		borderBottomLeftRadius: 4,         // Sharp corner on assistant side
	},
	text: {
		fontSize: 16,
		lineHeight: 22,
		marginBottom: spacing.xs,
	},
	userText: {
		color: colors.text.primary,
	},
	assistantText: {
		color: colors.text.primary,
	},
	timestamp: {
		fontSize: 12,
		lineHeight: 16,
	},
	userTimestamp: {
		color: colors.text.primary,
		textAlign: 'right',
	},
	assistantTimestamp: {
		color: colors.text.secondary,
		textAlign: 'left',
	},
});