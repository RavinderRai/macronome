/**
 * Spacing System
 * Consistent spacing scale for margins, padding, and gaps
 */

export const spacing = {
  // Base spacing unit (4px)
  xs: 4,
  sm: 8,
  md: 16,
  lg: 24,
  xl: 32,
  '2xl': 48,
  '3xl': 64,
  '4xl': 96,
};

// Named spacing for common use cases
export const namedSpacing = {
  // Component spacing
  componentPadding: spacing.md,      // 16px
  componentMargin: spacing.md,        // 16px
  componentGap: spacing.sm,          // 8px

  // Screen spacing
  screenPadding: spacing.lg,          // 24px
  screenMargin: spacing.lg,           // 24px

  // Card spacing
  cardPadding: spacing.md,            // 16px
  cardMargin: spacing.md,             // 16px
  cardGap: spacing.sm,               // 8px

  // List spacing
  listItemGap: spacing.md,           // 16px
  listItemPadding: spacing.md,        // 16px

  // Input spacing
  inputPadding: spacing.md,           // 16px
  inputGap: spacing.sm,               // 8px

  // Button spacing
  buttonPadding: spacing.md,         // 16px
  buttonGap: spacing.sm,             // 8px

  // Header spacing
  headerPadding: spacing.md,         // 16px
  headerHeight: 56,                   // Standard header height

  // Drawer spacing
  drawerPadding: spacing.lg,         // 24px
  drawerWidth: 280,                   // Standard drawer width

  // Bottom sheet spacing
  bottomSheetPadding: spacing.lg,    // 24px
  bottomSheetHeaderHeight: 48,        // Bottom sheet header

  // Chat spacing
  chatMessageGap: spacing.md,        // 16px
  chatInputPadding: spacing.md,      // 16px
  chatBubblePadding: spacing.md,      // 16px

  // Filter spacing
  filterChipGap: spacing.sm,         // 8px
  filterChipPadding: spacing.sm,      // 8px
  filterSectionPadding: spacing.md,   // 16px
};

// Type exports
export type Spacing = keyof typeof spacing;
export type NamedSpacing = keyof typeof namedSpacing;

