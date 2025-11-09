export interface BoundingBox {
    x: number;
    y: number;
    width: number;
    height: number;
  }
  
  export interface PantryItem {
    id: string; // Will be UUID when persisted
    name: string; // From classification step
    boundingBox?: BoundingBox; // For showing detection results
    category?: string;
    confirmed: boolean;
    confidence?: number;
    imageUrl?: string;
    detectedAt: Date;
  }

export interface PantryState {
    items: PantryItem[];
    isLoading: boolean;
    error: string | null;
}
