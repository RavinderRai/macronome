export interface MacroConstraints {
    carbs?: number;
    protein?: number;
    fat?: number;
}

export interface FilterConstraints {
    calories?: number;
    macros?: MacroConstraints;
    diet?: string;
    allergies: string[];
    prepTime?: number;
    mealType?: string;
}

export interface FilterState {
    constraints: FilterConstraints;
}