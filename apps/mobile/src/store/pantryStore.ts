import { create } from 'zustand';
import { v4 as uuidv4 } from 'uuid';
import type { PantryItem, PantryState } from '../types/pantry';

// Extend PantryState with actions
interface PantryStore extends PantryState {
	// Actions
	addItem: (item: Omit<PantryItem, 'id' | 'detectedAt'>) => void;
	removeItem: (id: string) => void;
	updateItem: (id: string, updates: Partial<PantryItem>) => void;
	confirmItem: (id: string) => void;
	unconfirmItem: (id: string) => void;
	addItems: (items: Omit<PantryItem, 'id' | 'detectedAt'>[]) => void;
	clearItems: () => void;
	setLoading: (isLoading: boolean) => void;
	setError: (error: string | null) => void;
	
	// TODO: Add API integration later
	// loadItems: () => Promise<void>;
	// saveItems: () => Promise<void>;
}

// Create the store
export const usePantryStore = create<PantryStore>((set) => ({
	// Initial state
	items: [],
	isLoading: false,
	error: null,

	// Actions
	addItem: (itemData) => {
		const newItem: PantryItem = {
			...itemData,
			id: uuidv4(),
			detectedAt: new Date(),
		};

		set((state) => ({
			items: [...state.items, newItem],
		}));
	},

	addItems: (itemsData) => {
		const newItems: PantryItem[] = itemsData.map((itemData) => ({
			...itemData,
			id: uuidv4(),
			detectedAt: new Date(),
		}));

		set((state) => ({
			items: [...state.items, ...newItems],
		}));
	},

	removeItem: (id) => {
		set((state) => ({
			items: state.items.filter((item) => item.id !== id),
		}));
	},

	updateItem: (id, updates) => {
		set((state) => ({
			items: state.items.map((item) =>
				item.id === id ? { ...item, ...updates } : item
			),
		}));
	},

	confirmItem: (id) => {
		set((state) => ({
			items: state.items.map((item) =>
				item.id === id ? { ...item, confirmed: true } : item
			),
		}));
	},

	unconfirmItem: (id) => {
		set((state) => ({
			items: state.items.map((item) =>
				item.id === id ? { ...item, confirmed: false } : item
			),
		}));
	},

	clearItems: () => {
		set({ items: [] });
	},

	setLoading: (isLoading) => {
		set({ isLoading });
	},

	setError: (error) => {
		set({ error });
	},
}));