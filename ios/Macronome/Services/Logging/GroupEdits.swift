import Foundation

/// Events for changing a logged group. Entries snapshot their macros, so anything not
/// being re-measured is copied from its original event rather than recomputed from
/// the food as it is now.
enum GroupEdits {
    /// A copy of an entry's original event with a new id, in another slot or group.
    static func copy(_ entry: Entry, ledger: Ledger, meal: MealSlot?, groupID: String, groupLabel: String?) -> Event {
        var f = ledger.events.last { $0.type == "entry_add" && $0.id == entry.id }?.fields ?? [:]
        f["id"] = nil
        f["ts"] = nil
        f["meal"] = JSONValue(meal?.rawValue)
        f["group_id"] = .string(groupID)
        f["group_label"] = groupLabel.map { .string($0) }
        if f["label"] == nil {
            // An entry with no stored event (should not happen): rebuild from the snapshot.
            return Commands.logEstimate(label: entry.label, macros: entry.macros, day: entry.eatenOn, meal: meal,
                                        source: entry.source ?? "text", confidence: entry.confidence ?? "low",
                                        groupID: groupID, groupLabel: groupLabel)
        }
        return Event.new("entry_add", f)
    }

    static func label(for group: LogGroup) -> String? {
        group.entries.count > 1 || group.entries.first?.groupLabel != nil ? group.label : nil
    }

    static func move(_ group: LogGroup, to slot: MealSlot, ledger: Ledger) -> [Event] {
        group.entries.map { copy($0, ledger: ledger, meal: slot, groupID: group.id, groupLabel: label(for: group)) }
    }

    /// The same foods again, now. Stored foods are logged fresh; estimates are copied.
    static func logAgain(_ group: LogGroup, ledger: Ledger, source: String = InputSource.text.rawValue) -> [Event] {
        let gid = EventID.make()
        let slot = MealSlot.guess()
        let groupLabel = label(for: group)
        return group.entries.compactMap { e in
            if let fid = e.foodID, let food = ledger.foods[fid],
               let ev = try? Commands.log(food, qty: e.qty, unit: e.unit, meal: slot, source: source, groupID: gid, groupLabel: groupLabel) {
                return ev
            }
            var ev = copy(e, ledger: ledger, meal: slot, groupID: gid, groupLabel: groupLabel)
            ev["eaten_on"] = .string(Clock.dayString())
            ev["eaten_at"] = .string(Clock.nowISO())
            return ev
        }
    }

    /// "Ate it" on a planned row: its components, or the plan's own estimate.
    static func ateIt(_ plan: PlannedItem, ledger: Ledger) -> [Event] {
        let gid = EventID.make()
        let slot = plan.meal ?? MealSlot.guess()
        let components = plan.components.isEmpty ? (plan.mealID.flatMap { ledger.meals[$0] }?.components ?? []) : plan.components
        let events = components.compactMap { c -> Event? in
            guard let food = ledger.foods[c.foodID] else { return nil }
            return try? Commands.log(food, qty: c.qty, unit: c.unit, meal: slot, source: "plan", groupID: gid,
                                     groupLabel: plan.label)
        }
        if !events.isEmpty { return events }
        return [Commands.logEstimate(label: plan.label, macros: plan.macros, meal: slot, source: "plan",
                                     confidence: "medium", groupID: gid, groupLabel: plan.label)]
    }

    /// The group with one entry's food swapped for another, keeping the amount when the
    /// new food can take it.
    static func swap(_ group: LogGroup, entryID: String, to food: Food, ledger: Ledger) -> [Event] {
        group.entries.compactMap { e in
            guard e.id == entryID else {
                return copy(e, ledger: ledger, meal: e.meal, groupID: group.id, groupLabel: label(for: group))
            }
            let amount = amount(keeping: e.qty, e.unit, for: food)
            return try? Commands.log(food, qty: amount.qty, unit: amount.unit, day: e.eatenOn, meal: e.meal,
                                     source: e.source ?? "text", groupID: group.id, groupLabel: label(for: group),
                                     at: Clock.parseISO(e.eatenAt) ?? Date())
        }
    }

    static func amount(keeping qty: Double, _ unit: String, for food: Food) -> (qty: Double, unit: String) {
        if (try? Ledger.resolveAmount(food, qty: qty, unit: unit)) != nil { return (qty, unit) }
        if food.basis == .serving || food.servingGrams != nil { return (1, food.servingLabel ?? "serving") }
        return (100, "g")
    }
}

/// Micronutrient keys from food-log ("sodium_mg") as readable rows.
enum Micros {
    static let order = [
        "sodium_mg", "potassium_mg", "calcium_mg", "iron_mg", "magnesium_mg", "zinc_mg", "phosphorus_mg",
        "sat_fat_g", "trans_fat_g", "sugar_g", "added_sugar_g", "cholesterol_mg", "omega3_g",
        "vitamin_a_ug", "vitamin_c_mg", "vitamin_d_ug", "vitamin_e_mg", "vitamin_k_ug", "thiamin_mg",
        "riboflavin_mg", "niacin_mg", "vitamin_b6_mg", "folate_ug", "vitamin_b12_ug", "caffeine_mg",
    ]
    static let names = [
        "sat_fat": "Saturated fat", "trans_fat": "Trans fat", "added_sugar": "Added sugar", "omega3": "Omega-3",
        "vitamin_b6": "Vitamin B6", "vitamin_b12": "Vitamin B12",
    ]

    static func split(_ key: String) -> (name: String, unit: String) {
        for (suffix, unit) in [("_mcg", "µg"), ("_ug", "µg"), ("_mg", "mg"), ("_g", "g")] where key.hasSuffix(suffix) {
            let base = String(key.dropLast(suffix.count))
            return (names[base] ?? pretty(base), unit)
        }
        return (names[key] ?? pretty(key), "")
    }

    private static func pretty(_ base: String) -> String {
        let words = base.split(separator: "_").map(String.init)
        guard let first = words.first else { return base }
        if first == "vitamin", words.count == 2 { return "Vitamin " + words[1].uppercased() }
        return ([first.prefix(1).uppercased() + first.dropFirst()] + words.dropFirst()).joined(separator: " ")
    }

    static func sorted(_ micros: [String: Double]) -> [(key: String, value: Double)] {
        micros.filter { $0.value > 0 }.sorted { a, b in
            let ia = order.firstIndex(of: a.key) ?? Int.max, ib = order.firstIndex(of: b.key) ?? Int.max
            return ia == ib ? a.key < b.key : ia < ib
        }
    }

    static func value(_ v: Double, unit: String) -> String {
        let text = v >= 100 ? Format.int(v) : Format.trim(v, digits: v < 10 ? 1 : 0)
        return unit.isEmpty ? text : "\(text) \(unit)"
    }
}
