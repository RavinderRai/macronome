/**
 * Midnight Rhythm Color Palette
 * Deep navy base • coral highlights • soft white cards
 */

export const colors = {
  // Primary colors - Deep navy base
  primary: {
    dark: '#0A0E27',      // Deepest navy
    main: '#1A1F3A',      // Main navy background
    light: '#2A2F4A',     // Lighter navy for cards
    lighter: '#3A3F5A',   // Even lighter for hover states
  },

  // Accent colors - Coral highlights
  accent: {
    coral: '#FF6B6B',     // Primary coral highlight
    coralLight: '#FF8E8E', // Lighter coral
    coralDark: '#E55555', // Darker coral
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
    secondary: '#DEE2E6',    // Light gray text
    muted: '#ADB5BD',        // Muted text
    inverse: '#212529',      // Dark text on light background
  },

  // Background colors
  background: {
    primary: '#1A1F3A',      // Main navy background
    secondary: '#0A0E27',    // Darker navy for sections
    card: '#F8F9FA',         // Soft white for cards
    drawer: '#2A2F4A',      // Lighter navy for drawer
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

