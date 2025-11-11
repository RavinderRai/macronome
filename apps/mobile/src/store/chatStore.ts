import { create } from 'zustand';
import { v4 as uuidv4 } from 'uuid';
import type { Message, ChatState } from '../types/chat';

interface ChatStore extends ChatState {
    addMessage: (message: Omit<Message, 'id' | 'timestamp'>) => void;
    clearMessages: () => void;
    setLoading: (isLoading: boolean) => void;
    setError: (error: string | null) => void;

    // TODO: Add API integration later
    // sendMessage: (text: string) => Promise<void>;
}

// Create the store
export const useChatStore = create<ChatStore>((set) => ({
    // Initial state
    messages: [],
    isLoading: false,
    error: null,

    // Actions
    addMessage: (messageData) => {
    const newMessage: Message = {
        ...messageData,
            id: uuidv4(),
        timestamp: new Date(),
    };

    set((state) => ({
        messages: [...state.messages, newMessage],
    }));
    },

    setLoading: (isLoading) => {
        set({ isLoading });
    },

    setError: (error) => {
    set({ error });
    },

    clearMessages: () => {
    set({ messages: [] });
    },
}));
