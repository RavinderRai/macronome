import { create } from 'zustand';

interface UIState {
	// Filter section state
	filtersCollapsed: boolean;
	
	// Drawer state
	drawerOpen: boolean;
	
	// Other UI toggles can be added here
	// showOnboarding: boolean;
	// theme: 'light' | 'dark';
}

interface UIStore extends UIState {
    // Actions
    toggleFilters: () => void;
    setFiltersCollapsed: (collapsed: boolean) => void;
    toggleDrawer: () => void;
    setDrawerOpen: (open: boolean) => void;
    resetUI: () => void;
}

// Create the store
export const useUIStore = create<UIStore>((set) => ({
	// Initial state
	filtersCollapsed: true, // Start collapsed
	drawerOpen: false, // Start closed

	// Actions
	toggleFilters: () => {
		set((state) => ({
			filtersCollapsed: !state.filtersCollapsed,
		}));
	},

	setFiltersCollapsed: (collapsed) => {
		set({ filtersCollapsed: collapsed });
	},

	toggleDrawer: () => {
		set((state) => ({
			drawerOpen: !state.drawerOpen,
		}));
	},

	setDrawerOpen: (open) => {
		set({ drawerOpen: open });
	},

	resetUI: () => {
		set({
			filtersCollapsed: true,
			drawerOpen: false,
		});
	},
}));