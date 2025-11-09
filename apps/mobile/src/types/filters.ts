export type MacroLevel = 'low' | 'moderate' | 'high';

export type MacroValue = MacroLevel | number;

export interface MacroConstraints {
    carbs?: MacroValue;
    protein?: MacroValue;
    fat?: MacroValue;
}

export interface FilterConstraints {
    calories?: number;
    macros?: MacroConstraints;
    diet?: string;
    excludedIngredients: string[];
    prepTime?: number;
}

export interface FilterState {
    constraints: FilterConstraints;
}