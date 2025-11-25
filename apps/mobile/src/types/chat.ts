export type MessageType = 'user' | 'assistant' | 'system';

export interface Message {
    id: string;
    text: string;
    type: MessageType;
    timestamp: Date;
    component?: 'MealRecommendationCard' | 'ErrorCard'; // Component type for structured rendering
    data?: any; // Structured data for component rendering
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