export interface MacroConstraints {
    carbs?: number;
    protein?: number;
    fat?: number;
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