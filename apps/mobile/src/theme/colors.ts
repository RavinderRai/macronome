/**
 * Warm Sunset Color Palette
 * Deep charcoal base • warm orange accents • inviting and food-friendly
 */

export const colors = {
  // Primary colors - Deep charcoal base
  primary: {
    dark: '#0F1419',      // Deepest charcoal
    main: '#1E293B',      // Main slate background
    light: '#2A2F4A',     // Lighter slate for cards
    lighter: '#334155',   // Even lighter for hover states
  },

  // Accent colors - Warm sunset
  accent: {
    coral: '#FF6B35',     // Primary warm orange
    coralLight: '#FF8C42', // Bright amber
    coralDark: '#E55555', // Darker orange-red
    amber: '#FFB347',     // Soft amber
    peach: '#FFB88C',     // Soft peach
  },

  // Neutral colors - Soft white cards
  neutral: {
    white: '#FFFFFF',
    offWhite: '#F8F9FA',  // Soft white for cards
    gray100: '#E9ECEF',
    gray200: '#DEE2E6',
    gray300: '#CED4DA',
    gray400: '#ADB5BD',
    gray500: '#6C757D',
    gray600: '#495057',
    gray700: '#343A40',
    gray800: '#212529',
    black: '#000000',
  },

  // Semantic colors
  semantic: {
    success: '#28A745',
    warning: '#FFC107',
    error: '#DC3545',
    info: '#17A2B8',
  },

  // Text colors
  text: {
    primary: '#FFFFFF',      // White text on dark background
    secondary: '#E2E8F0',    // Light slate-gray text
    muted: '#94A3B8',        // Muted slate text
    inverse: '#1E293B',      // Dark text on light background
  },

  // Background colors
  background: {
    primary: '#1E293B',      // Main slate background
    secondary: '#0F1419',    // Darker charcoal for sections
    card: '#1E293B',         // Dark slate for cards (was white)
    drawer: '#2A2F4A',      // Lighter slate for drawer
  },

  // Border colors
  border: {
    light: '#3A3F5A',
    medium: '#2A2F4A',
    dark: '#1A1F3A',
  },
};

// Type export for TypeScript
export type ColorName = keyof typeof colors;
export type ColorValue = string;

