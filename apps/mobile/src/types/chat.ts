export type MessageType = 'user' | 'assistant' | 'system';

export interface Message {
    id: string;
    text: string;
    type: MessageType;
    timestamp: Date;
}

export interface Meal {
    id: string;
    name: string;
    description: string;
    imageUrl?: string;
    prepTime?: number; // in minutes
    calories?: number;
    ingredients: string[];
    reasoning?: string; // LLM reasoning for why this meal was recommended
}

export interface ChatState {
    messages: Message[];
    isLoading: boolean;
    error: string | null;
}