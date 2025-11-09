/**
 * App-wide Constants
 * Configuration values and constants used throughout the app
 */

// App configuration
export const APP_CONFIG = {
  name: 'Macronome',
  tagline: 'Eat in Rhythm, Not in Restriction',
  version: '1.0.0',
} as const;

// API Configuration (TODO: Update when backend is ready)
export const API_CONFIG = {
  // TODO: Set up FastAPI base URL
  baseURL: __DEV__ ? 'http://localhost:8000' : 'https://api.macronome.com',
  
  // TODO: Set up Supabase configuration
  supabase: {
    url: '', // TODO: Add Supabase URL
    anonKey: '', // TODO: Add Supabase anon key
  },
  
  // API endpoints (TODO: Update when endpoints are ready)
  endpoints: {
    chat: '/api/chat',
    recommendations: '/api/recommendations',
    pantry: {
      scan: '/api/pantry/scan',
      items: '/api/pantry/items',
      add: '/api/pantry/add',
      remove: '/api/pantry/remove',
    },
  },
  
  // Request timeouts
  timeout: 30000, // 30 seconds
} as const;

// UI Constants
export const UI_CONSTANTS = {
  // Animation durations (milliseconds)
  animation: {
    fast: 150,
    normal: 300,
    slow: 500,
  },
  
  // Debounce delays (milliseconds)
  debounce: {
    search: 300,
    input: 500,
  },
  
  // Limits
  limits: {
    maxChatMessages: 100,
    maxPantryItems: 200,
    maxFilterChips: 10,
    maxMessageLength: 500,
  },
  
  // Dimensions
  dimensions: {
    headerHeight: 56,
    drawerWidth: 280,
    bottomSheetMaxHeight: '80%',
    chatInputMinHeight: 50,
    chatInputMaxHeight: 120,
  },
} as const;

// Filter Constants
export const FILTER_CONSTANTS = {
  // Calorie ranges
  calorieRanges: [
    { label: 'Any', value: null },
    { label: '300 or less', value: 300 },
    { label: '500 or less', value: 500 },
    { label: '700 or less', value: 700 },
    { label: '1000 or less', value: 1000 },
  ],
  
  // Macro levels
  macroLevels: [
    { label: 'Low', value: 'low' },
    { label: 'Moderate', value: 'moderate' },
    { label: 'High', value: 'high' },
  ],
  
  // Diet types
  dietTypes: [
    { label: 'Any', value: 'any' },
    { label: 'Vegan', value: 'vegan' },
    { label: 'Vegetarian', value: 'vegetarian' },
    { label: 'Keto', value: 'keto' },
    { label: 'Paleo', value: 'paleo' },
    { label: 'Mediterranean', value: 'mediterranean' },
    { label: 'Low Carb', value: 'low_carb' },
    { label: 'High Protein', value: 'high_protein' },
  ],
} as const;

// Pantry Constants
export const PANTRY_CONSTANTS = {
  // Scan configuration
  scan: {
    maxImageSize: 5 * 1024 * 1024, // 5MB
    supportedFormats: ['image/jpeg', 'image/png', 'image/jpg'],
    quality: 0.8, // Image compression quality
  },
  
  // Item categories (for future use)
  categories: [
    'produce',
    'dairy',
    'meat',
    'grains',
    'snacks',
    'beverages',
    'condiments',
    'other',
  ],
} as const;

// Chat Constants
export const CHAT_CONSTANTS = {
  // Message types
  messageTypes: {
    user: 'user',
    assistant: 'assistant',
    system: 'system',
  },
  
  // Placeholder text
  placeholders: {
    input: 'Type a message...',
    empty: 'Start a conversation to get meal recommendations!',
  },
} as const;

// Export all constants as a single object for convenience
export const CONSTANTS = {
  APP_CONFIG,
  API_CONFIG,
  UI_CONSTANTS,
  FILTER_CONSTANTS,
  PANTRY_CONSTANTS,
  CHAT_CONSTANTS,
} as const;

