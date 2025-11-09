/**
 * Typography System
 * Font styles and text configurations
 */

import { Platform } from 'react-native';

export const typography = {
  // Font families
  fontFamily: {
    // Using system fonts for now - can add custom fonts later
    regular: Platform.select({
      ios: 'System',
      android: 'Roboto',
      default: 'System',
    }),
    serif: Platform.select({
      ios: 'Georgia',
      android: 'serif',
      default: 'serif',
    }),
    mono: Platform.select({
      ios: 'Courier',
      android: 'monospace',
      default: 'monospace',
    }),
  },

  // Font sizes
  fontSize: {
    xs: 12,
    sm: 14,
    base: 16,
    lg: 18,
    xl: 20,
    '2xl': 24,
    '3xl': 30,
    '4xl': 36,
    '5xl': 48,
  },

  // Font weights
  fontWeight: {
    light: '300',
    normal: '400',
    medium: '500',
    semibold: '600',
    bold: '700',
  },

  // Line heights
  lineHeight: {
    tight: 1.2,
    normal: 1.5,
    relaxed: 1.75,
    loose: 2,
  },

  // Text styles (pre-configured combinations)
  textStyles: {
    // Display styles
    display: {
      fontSize: 36,
      fontWeight: '700' as '700',
      lineHeight: 1.2,
      fontFamily: 'serif',
    },
    
    // Heading styles
    h1: {
      fontSize: 30,
      fontWeight: '700' as '700',
      lineHeight: 1.3,
    },
    h2: {
      fontSize: 24,
      fontWeight: '600' as '600',
      lineHeight: 1.3,
    },
    h3: {
      fontSize: 20,
      fontWeight: '600' as '600',
      lineHeight: 1.4,
    },
    h4: {
      fontSize: 18,
      fontWeight: '600' as '600',
      lineHeight: 1.4,
    },

    // Body styles
    body: {
      fontSize: 16,
      fontWeight: '400' as '400',
      lineHeight: 1.5,
    },
    bodyLarge: {
      fontSize: 18,
      fontWeight: '400' as '400',
      lineHeight: 1.5,
    },
    bodySmall: {
      fontSize: 14,
      fontWeight: '400' as '400',
      lineHeight: 1.5,
    },

    // UI styles
    button: {
      fontSize: 16,
      fontWeight: '600' as '600',
      lineHeight: 1.5,
    },
    caption: {
      fontSize: 12,
      fontWeight: '400' as '400',
      lineHeight: 1.5,
    },
    label: {
      fontSize: 14,
      fontWeight: '500' as '500',
      lineHeight: 1.5,
    },
  },
};

// Type exports
export type FontSize = keyof typeof typography.fontSize;
export type FontWeight = '300' | '400' | '500' | '600' | '700';
export type TextStyle = keyof typeof typography.textStyles;

