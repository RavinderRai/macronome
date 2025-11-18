import { create } from 'zustand';
import { v4 as uuidv4 } from 'uuid';
import type { PantryItem, PantryState } from '../types/pantry';
import { addPantryItems, deletePantryItem, getPantryItems, updatePantryItem } from '../services/api/pantry';

// Extend PantryState with actions
interface PantryStore extends PantryState {
	// Actions
	addItem: (item: Omit<PantryItem, 'id' | 'detectedAt'>) => void;
	removeItem: (id: string) => Promise<void>;
	updateItem: (id: string, updates: Partial<PantryItem>) => Promise<void>;
	confirmItem: (id: string) => Promise<void>;
	unconfirmItem: (id: string) => Promise<void>;
	addItems: (items: Omit<PantryItem, 'id' | 'detectedAt'>[], imageId?: string) => Promise<void>;
	clearItems: () => void;
	setLoading: (isLoading: boolean) => void;
	setError: (error: string | null) => void;
	
	// API integration
	loadItems: () => Promise<void>;
	syncItemsToBackend: (items: Omit<PantryItem, 'id' | 'detectedAt'>[], imageId?: string) => Promise<void>;
}

// Create the store
export const usePantryStore = create<PantryStore>((set, get) => ({
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

	addItems: async (itemsData, imageId?: string) => {
		const newItems: PantryItem[] = itemsData.map((itemData) => ({
			...itemData,
			id: uuidv4(),
			detectedAt: new Date(),
		}));

		set((state) => ({
			items: [...state.items, ...newItems],
		}));

		// Sync to backend with image_id if provided
		try {
			const { syncItemsToBackend } = get();
			await syncItemsToBackend(itemsData, imageId);
		} catch (error) {
			console.error('❌ Failed to sync items to backend:', error);
			// Don't throw - UI should still work if backend sync fails
		}
	},

	removeItem: async (id) => {
		// Get item before removing to check if it has a backend ID
		const item = get().items.find((item: PantryItem) => item.id === id);
		
		set((state) => ({
			items: state.items.filter((item) => item.id !== id),
		}));

		// Delete from backend if it has a backend ID (from database)
		// Local items (from scanning) don't have backend IDs yet
		if (item && 'user_id' in item) {
			try {
				// Extract backend ID if it exists (items from backend have numeric/string IDs)
				// For now, we'll check if the item structure suggests it's from backend
				// This is a simplified check - you may need to adjust based on your ID format
				const backendId = (item as any).id; // Use the same ID
				await deletePantryItem(backendId);
			} catch (error) {
				console.error('❌ Failed to delete item from backend:', error);
				// Don't throw - item is already removed from local state
			}
		}
	},

	updateItem: async (id, updates) => {
		// Update local state optimistically
		set((state) => ({
			items: state.items.map((item) =>
				item.id === id ? { ...item, ...updates } : item
			),
		}));

		// Sync to backend if item exists in backend (has backend ID format)
		// Check if item has a backend-like ID (not just a UUID from frontend)
		const item = get().items.find((item: PantryItem) => item.id === id);
		if (item) {
			try {
				// Try to update in backend (will fail gracefully if item doesn't exist there)
				await updatePantryItem(id, updates);
				console.log('✅ Synced item update to backend');
			} catch (error) {
				console.error('❌ Failed to sync item update to backend:', error);
				// Don't throw - local state is already updated
			}
		}
	},

	confirmItem: async (id) => {
		// Update local state optimistically
		set((state) => ({
			items: state.items.map((item) =>
				item.id === id ? { ...item, confirmed: true } : item
			),
		}));

		// Sync to backend
		try {
			await updatePantryItem(id, { confirmed: true });
			console.log('✅ Synced confirm status to backend');
		} catch (error) {
			console.error('❌ Failed to sync confirm status to backend:', error);
			// Don't throw - local state is already updated
		}
	},

	unconfirmItem: async (id) => {
		// Update local state optimistically
		set((state) => ({
			items: state.items.map((item) =>
				item.id === id ? { ...item, confirmed: false } : item
			),
		}));

		// Sync to backend
		try {
			await updatePantryItem(id, { confirmed: false });
			console.log('✅ Synced unconfirm status to backend');
		} catch (error) {
			console.error('❌ Failed to sync unconfirm status to backend:', error);
			// Don't throw - local state is already updated
		}
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

	loadItems: async () => {
		const { setLoading, setError } = get();
		try {
			setLoading(true);
			setError(null);
			
			const response = await getPantryItems();
			
			// Transform backend items to frontend format
			const items: PantryItem[] = response.items.map((item) => ({
				id: item.id,
				name: item.name,
				category: item.category,
				confirmed: item.confirmed,
				confidence: item.confidence,
				detectedAt: new Date(item.created_at),
			}));
			
			set({ items, isLoading: false });
			console.log('✅ Loaded', items.length, 'pantry items from backend');
		} catch (error) {
			console.error('❌ Failed to load pantry items:', error);
			setError(error instanceof Error ? error.message : 'Failed to load pantry items');
			set({ isLoading: false });
		}
	},

	syncItemsToBackend: async (itemsData, imageId?: string) => {
		try {
			// Transform frontend items to backend format
			const itemsToAdd = itemsData.map((item) => ({
				name: item.name,
				category: item.category,
				confirmed: item.confirmed ?? true,
				confidence: item.confidence,
				image_id: imageId, // Link all items from same scan to the same image
			}));

			const response = await addPantryItems(itemsToAdd);
			console.log('✅ Synced', response.items.length, 'items to backend');
			
			// Update local items with backend IDs if needed
			// For now, we'll keep the local UUIDs since they're already in the store
		} catch (error) {
			console.error('❌ Failed to sync items to backend:', error);
			throw error;
		}
	},
}));