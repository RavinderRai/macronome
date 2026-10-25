import Foundation

/// Builds the events behind each action, mirroring fl.py's commands so a log written
/// here reads the same in `fl.py today`.
enum Commands {
    static let scaledKeys = ["kcal", "protein", "carbs", "fat", "fiber", "fiber_soluble", "fiber_insoluble"]

    /// `fl.py log`: a known food at an amount. Macros are snapshotted on the entry.
    static func log(_ food: Food, qty: Double, unit: String, day: String = Clock.dayString(),
                    meal: MealSlot? = nil, source: String = "text", confidence: String = "high",
                    note: String? = nil, groupID: String? = nil, groupLabel: String? = nil,
                    at date: Date = Date()) throws -> Event {
        let (factor, grams) = try Ledger.resolveAmount(food, qty: qty, unit: unit)
        let base: [String: Double?] = [
            "kcal": food.kcal, "protein": food.protein, "carbs": food.carbs, "fat": food.fat,
            "fiber": food.fiber, "fiber_soluble": food.fiberSoluble, "fiber_insoluble": food.fiberInsoluble,
        ]
        var f: [String: JSONValue] = [
            "food_id": .string(food.id), "label": .string(food.name), "qty": .number(qty),
            "unit": .string(unit.lowercased()), "grams": JSONValue(grams),
            "micros": Ledger.microsJSON(food.micros.mapValues { $0 * factor }),
            "eaten_on": .string(day), "eaten_at": .string(Clock.nowISO(date)),
            "meal": JSONValue(meal?.rawValue), "source": .string(source), "confidence": .string(confidence),
            "note": JSONValue(note),
        ]
        for key in scaledKeys {
            f[key] = JSONValue((base[key] ?? nil).map { Ledger.round2($0 * factor) })
        }
        if let groupID { f["group_id"] = .string(groupID) }
        if let groupLabel { f["group_label"] = .string(groupLabel) }
        return Event.new("entry_add", f)
    }

    /// `fl.py logx`: a one-off estimate with no stored food (restaurant, plate photo).
    static func logEstimate(label: String, macros: Macros, grams: Double? = nil, day: String = Clock.dayString(),
                            meal: MealSlot? = nil, source: String = "estimate", confidence: String = "low",
                            note: String? = nil, micros: [String: Double] = [:], groupID: String? = nil,
                            groupLabel: String? = nil) -> Event {
        var f: [String: JSONValue] = [
            "food_id": .null, "label": .string(label), "qty": 1, "unit": "serving", "grams": JSONValue(grams),
            "kcal": .number(macros.kcal), "protein": .number(macros.protein), "carbs": .number(macros.carbs),
            "fat": .number(macros.fat), "fiber": macros.fiber > 0 ? .number(macros.fiber) : .null,
            "fiber_soluble": .null, "fiber_insoluble": .null, "micros": Ledger.microsJSON(micros),
            "eaten_on": .string(day), "eaten_at": .string(Clock.nowISO()), "meal": JSONValue(meal?.rawValue),
            "source": .string(source), "confidence": .string(confidence), "note": JSONValue(note),
        ]
        if let groupID { f["group_id"] = .string(groupID) }
        if let groupLabel { f["group_label"] = .string(groupLabel) }
        return Event.new("entry_add", f)
    }

    /// Every component of a usual meal as its own entry, sharing one group.
    static func log(_ meal: UsualMeal, in ledger: Ledger, overrides: [String: (qty: Double, unit: String)] = [:],
                    day: String = Clock.dayString(), slot: MealSlot? = nil, source: String = "text") throws -> [Event] {
        let gid = EventID.make()
        return try meal.components.compactMap { c in
            guard let food = ledger.foods[c.foodID] else { return nil }
            let amount = overrides[c.foodID] ?? (c.qty, c.unit)
            return try log(food, qty: amount.qty, unit: amount.unit, day: day,
                           meal: slot ?? meal.slot ?? MealSlot.guess(), source: source,
                           groupID: gid, groupLabel: meal.name)
        }
    }

    static func deleteEntry(_ id: String) -> Event { Event.new("entry_delete", ["target": .string(id)]) }

    static func addFood(_ food: Food) -> Event {
        var f = Ledger.foodFields(food)
        f["source"] = .string(food.source ?? "manual")
        return Event.new("food_add", f)
    }

    static func updateFood(_ id: String, fields: [String: JSONValue]) -> Event {
        Event.new("food_update", ["target": .string(id), "fields": .object(fields)])
    }

    static func deleteFood(_ id: String) -> Event { Event.new("food_delete", ["target": .string(id)]) }

    static func setProfile(_ key: String, _ value: String) -> Event {
        Event.new("profile_set", ["key": .string(key), "value": .string(value)])
    }

    static func forgetMemory(_ key: String) -> Event { Event.new("memory_delete", ["key": .string(key)]) }

    static func setTarget(_ key: MacroStatus.Key, _ value: Double, day: String? = nil) -> Event {
        if let day {
            return Event.new("day_target", ["day": .string(day), "key": .string(key.rawValue), "value": .string(String(value))])
        }
        return setProfile("target_\(key.rawValue)", String(value))
    }

    static func note(_ text: String, day: String = Clock.dayString()) -> Event {
        Event.new("day_note", ["day": .string(day), "note": .string(text)])
    }

    static func setMeal(_ meal: UsualMeal) -> Event {
        Event.new("meal_set", [
            "meal_id": .string(meal.id), "name": .string(meal.name),
            "aliases": .array(meal.aliases.map { .string($0) }), "slot": JSONValue(meal.slot?.rawValue),
            "components": Ledger.componentsJSON(meal.components), "note": JSONValue(meal.note),
        ])
    }

    static func deleteMeal(_ id: String) -> Event { Event.new("meal_delete", ["target": .string(id)]) }

    static func plan(label: String, detail: String? = nil, macros: Macros, day: String = Clock.dayString(),
                     meal: MealSlot? = nil, mealID: String? = nil, components: [UsualMeal.Component] = []) -> Event {
        Event.new("plan_add", [
            "day": .string(day), "label": .string(label), "detail": JSONValue(detail),
            "meal": JSONValue(meal?.rawValue), "kcal": .number(macros.kcal), "protein": .number(macros.protein),
            "carbs": .number(macros.carbs), "fat": .number(macros.fat), "fiber": .number(macros.fiber),
            "meal_ref": JSONValue(mealID), "components": Ledger.componentsJSON(components),
        ])
    }

    static func deletePlan(_ id: String) -> Event { Event.new("plan_delete", ["target": .string(id)]) }
}
