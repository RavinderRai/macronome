import Foundation

/// The chat's system prompt, built from the ledger. It follows food-log/CLAUDE.md:
/// the profile is read before every suggestion, every option carries kcal and protein,
/// and the model never does the arithmetic. Options come back as components, and the
/// app computes their numbers from the library.
enum ChatPrompt {
    /// Profile notes that change what should be suggested; listed first.
    static let priorityKeys = ["diet", "allergies", "dislikes", "suggestion_format", "snack_definition", "prep_times",
                               "fat_note"]

    static let rules = """
    You are the planning chat inside Macronome, Ravi's personal macro tracker. He asks what to eat, how a \
    day will land, or tells you what he ate. Be brief and plain: one to three short sentences, no markdown, \
    no bullet lists. The app shows the details of each option on a card.

    How to answer:
    - Read the notes about Ravi below before suggesting anything. They came from him correcting earlier \
    answers and override general nutrition advice. Respect his diet, dislikes, snack definition and prep times.
    - Never do arithmetic and never state calories, protein or other macros for an option. The app computes \
    every option's numbers from his food library and shows kcal and protein on the card. You may repeat \
    numbers that appear in the context below exactly as written (for example what is left today).
    - Build every option only from foods in the library, as components with the food's id, a quantity and \
    a unit. Units: "g", "ml", "serving", or the food's serving label (for example "cup", "scoop", "slice"). \
    Foods stored per 100 g can be given in grams.
    - When an option is one of his usual meals, set meal_id and list its components with the amounts you \
    suggest; change amounts to fit the day rather than inventing new meals.
    - Offer one to three options that fit what is left. Put the best fit first.
    - detail is a short line about prep, like "About 20 min · air fryer" or "Instant · pour". Use his \
    prep times.
    - slot is breakfast, lunch, dinner or snack, when it is clear.
    - If he says he ate something, return it as a single option with the right components so he can log it.
    - If nothing in the library fits, say so and return no options. Never invent food ids.

    Reply with one JSON object and nothing else:
    {"text": "...", "options": [{"title": "Potato bowl, 300 g potato", "detail": "About 20 min · air fryer", \
    "meal_id": "potato_bowl", "slot": "dinner", "components": [{"food_id": "a1b2c3", "qty": 300, "unit": "g"}]}]}
    Use "options": [] when there is nothing to offer.
    """

    /// [stable, day]: the stable part (rules, notes, meals, library) changes only when
    /// the library or profile does, so it can be cached; the day part changes per log.
    static func system(ledger: Ledger, day: String = Clock.dayString(), now: Date = Date(), compact: Bool = false) -> [String] {
        [stableContext(ledger: ledger, compact: compact), dayContext(ledger: ledger, day: day, now: now)]
    }

    // MARK: stable

    static func stableContext(ledger: Ledger, compact: Bool = false) -> String {
        var out = [rules]
        out.append(notesSection(ledger: ledger, compact: compact))
        let meals = mealsSection(ledger: ledger)
        if !meals.isEmpty { out.append(meals) }
        out.append(foodsSection(ledger: ledger, compact: compact))
        return out.joined(separator: "\n\n")
    }

    static func notesSection(ledger: Ledger, compact: Bool) -> String {
        let notes = ledger.memoryNotes
        let byKey = Dictionary(notes.map { ($0.key, $0.value) }, uniquingKeysWith: { a, _ in a })
        var lines: [String] = []
        for key in priorityKeys {
            if let v = byKey[key] { lines.append("- \(key): \(clip(v, compact ? 240 : nil))") }
        }
        if !compact {
            for n in notes.sorted(by: { $0.key < $1.key }) where !priorityKeys.contains(n.key) {
                lines.append("- \(n.key): \(n.value)")
            }
            // Staple meals Ravi described in words (meal_* profile keys).
            for (k, v) in ledger.profile.sorted(by: { $0.key < $1.key })
            where k.hasPrefix("meal_") && !ledger.deletedMemory.contains(k) {
                lines.append("- \(k): \(v)")
            }
        }
        if lines.isEmpty { lines.append("- (no notes yet)") }
        return "Notes about Ravi:\n" + lines.joined(separator: "\n")
    }

    static func mealsSection(ledger: Ledger) -> String {
        let meals = ledger.sortedMeals
        guard !meals.isEmpty else { return "" }
        let lines = meals.map { m -> String in
            let parts = m.components.compactMap { c -> String? in
                guard let f = ledger.foods[c.foodID] else { return nil }
                return "\(Format.trim(c.qty, digits: 2)) \(c.unit) \(f.name) [\(f.id)]"
            }
            let total = ledger.preview(m)
            var head = "\(m.id) | \(m.name)"
            if !m.aliases.isEmpty { head += " (aka \(m.aliases.joined(separator: ", ")))" }
            if let s = m.slot { head += " | \(s.rawValue)" }
            return "- \(head) | \(parts.joined(separator: " + ")) | \(Format.int(total.kcal)) kcal, \(Format.int(total.protein)) g protein"
        }
        return "Usual meals (meal_id | name | components at default amounts | numbers computed by the app):\n"
            + lines.joined(separator: "\n")
    }

    static func foodsSection(ledger: Ledger, compact: Bool) -> String {
        let foods = ledger.sortedFoods
        if compact {
            let lines = foods.prefix(80).map { "- \($0.id) | \($0.name) | \(unitHint($0))" }
            return "Food library (id | name | units):\n" + lines.joined(separator: "\n")
        }
        let lines = foods.map { f -> String in
            var s = "- \(f.id) | \(f.name) | per \(f.perLabel): \(Format.trim(f.kcal)) kcal, P \(Format.trim(f.protein)), "
                + "C \(Format.trim(f.carbs)), F \(Format.trim(f.fat))"
            if let fib = f.fiber, fib > 0 { s += ", fiber \(Format.trim(fib))" }
            s += " | " + unitHint(f)
            if !f.aliases.isEmpty { s += " | aka \(f.aliases.prefix(4).joined(separator: ", "))" }
            return s
        }
        return "Food library (id | name | macros per basis | units):\n" + (lines.isEmpty ? "- (empty)" : lines.joined(separator: "\n"))
    }

    /// "1 cup = 40 g", "grams", "1 serving".
    static func unitHint(_ f: Food) -> String {
        let label = f.servingLabel ?? "serving"
        switch (f.basis, f.servingGrams) {
        case (.per100g, let g?): return "g, or 1 \(label) = \(Format.trim(g)) g"
        case (.per100g, nil): return "g"
        case (.serving, let g?): return "1 \(label) = \(Format.trim(g)) g"
        case (.serving, nil): return "1 \(label)"
        }
    }

    // MARK: day

    static func dayContext(ledger: Ledger, day: String, now: Date) -> String {
        let tf = DateFormatter()
        tf.dateFormat = "EEEE d MMMM yyyy, h:mm a"
        var out = ["Today: \(tf.string(from: now)) (\(day)). Likely next meal: \(MealSlot.guess(at: now).rawValue)."]

        let status = ledger.macroStatus(on: day)
        var lines: [String] = []
        for s in status {
            let unit = s.key == .kcal ? "kcal" : "g"
            var line = "- \(s.label): eaten \(Format.int(s.eaten)) \(unit)"
            if let t = s.target {
                line += ", target \(Format.int(t))"
                if let left = s.left {
                    if s.isFloor {
                        line += left > 0 ? ", \(Format.int(left)) to go (a floor, more is fine)" : ", floor reached"
                    } else {
                        line += left >= 0 ? ", \(Format.int(left)) left" : ", \(Format.int(-left)) over"
                    }
                }
            }
            lines.append(line)
        }
        var head = "Today so far (computed by the app)"
        if ledger.hasOverride(on: day) { head += ", with a one-day target override" }
        if ledger.carbMode == "net" { head += "; carbs are net of fiber" }
        out.append(head + ":\n" + lines.joined(separator: "\n"))

        let plans = ledger.plans(on: day)
        if !plans.isEmpty {
            let p = plans.map { "- \($0.meal?.rawValue ?? "later"): \($0.label), \(Format.int($0.macros.kcal)) kcal, \(Format.int($0.macros.protein)) g protein" }
            let planned = ledger.plannedMacros(on: day)
            var s = "Already planned for later today:\n" + p.joined(separator: "\n")
            if let left = ledger.status(.kcal, on: day).left {
                s += "\nAfter the plan: \(Format.int(left - planned.kcal)) kcal left"
            }
            out.append(s)
        }

        let groups = ledger.groups(on: day)
        if !groups.isEmpty {
            let g = groups.map { "- \($0.meal?.rawValue ?? "logged"): \($0.label), \(Format.int($0.macros.kcal)) kcal, \(Format.int($0.macros.protein)) g protein" }
            out.append("Eaten today:\n" + g.joined(separator: "\n"))
        }
        if let note = ledger.dayNotes[day], !note.isEmpty { out.append("Note for today: \(note)") }
        if let bank = ledger.profile["calorie_bank"], !bank.isEmpty { out.append("Calorie bank: \(bank)") }
        return out.joined(separator: "\n\n")
    }

    private static func clip(_ s: String, _ n: Int?) -> String {
        guard let n, s.count > n else { return s }
        return String(s.prefix(n)) + "…"
    }
}

/// Turns the model's answer into a message with options whose numbers come from the
/// ledger. Tolerates code fences, prose around the JSON, string numbers, and food
/// ids that do not exist (those components are dropped).
enum ChatReplyParser {
    static func parse(_ raw: String, ledger: Ledger) -> ChatMessage {
        guard let obj = jsonObject(in: raw) else {
            return ChatMessage(role: .assistant, text: stripFences(raw))
        }
        let text = obj["text"]?.string ?? obj["message"]?.string ?? obj["reply"]?.string ?? ""
        let options = (obj["options"]?.array ?? []).compactMap { $0.object.flatMap { option($0, ledger: ledger) } }
        if text.isEmpty && options.isEmpty { return ChatMessage(role: .assistant, text: stripFences(raw)) }
        return ChatMessage(role: .assistant, text: text, options: options)
    }

    /// One option, with components checked against the library and macros recomputed.
    static func option(_ o: [String: JSONValue], ledger: Ledger) -> MealOption? {
        let mealID = o["meal_id"]?.string.flatMap { ledger.meals[$0] != nil ? $0 : ledger.findMeal($0)?.id }
        var components = (o["components"]?.array ?? []).compactMap { c -> UsualMeal.Component? in
            guard let c = c.object else { return nil }
            return component(c, ledger: ledger)
        }
        if components.isEmpty, let mealID, let meal = ledger.meals[mealID] { components = meal.components }
        components = components.filter { c in ledger.foods[c.foodID].flatMap { ledger.preview($0, qty: c.qty, unit: c.unit) } != nil }
        guard !components.isEmpty else { return nil }
        let m = macros(components, ledger: ledger)
        let title = o["title"]?.string ?? mealID.flatMap { ledger.meals[$0]?.name } ?? "Option"
        let detail = o["detail"]?.string.flatMap { $0.isEmpty ? nil : $0 }
        let slot = o["slot"]?.string.flatMap { MealSlot(rawValue: $0.lowercased()) }
        return MealOption(title: title, detail: detail, mealID: mealID, components: components, kcal: m.kcal,
                          protein: m.protein, carbs: m.carbs, fat: m.fat, slot: slot)
    }

    static func component(_ c: [String: JSONValue], ledger: Ledger) -> UsualMeal.Component? {
        let id = c["food_id"]?.string ?? c["id"]?.string ?? ""
        var food = ledger.foods[id]
        // A model that writes the food's name instead of its id is rescued only when
        // the name resolves to exactly one food.
        if food == nil {
            let name = c["name"]?.string ?? id
            if name.count >= 3, case .found(let f) = ledger.findFood(name) { food = f }
        }
        guard let food else { return nil }
        let qty = c["qty"]?.double ?? c["quantity"]?.double ?? 1
        guard qty > 0 else { return nil }
        let unit = (c["unit"]?.string ?? "serving").trimmingCharacters(in: .whitespaces).lowercased()
        return UsualMeal.Component(foodID: food.id, qty: qty, unit: unit.isEmpty ? "serving" : unit)
    }

    static func macros(_ components: [UsualMeal.Component], ledger: Ledger) -> Macros {
        components.reduce(.zero) { sum, c in
            guard let f = ledger.foods[c.foodID], let m = ledger.preview(f, qty: c.qty, unit: c.unit) else { return sum }
            return sum + m
        }
    }

    // MARK: JSON extraction

    static func stripFences(_ s: String) -> String {
        var t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.hasPrefix("```") {
            if let nl = t.firstIndex(of: "\n") { t = String(t[t.index(after: nl)...]) } else { t = String(t.dropFirst(3)) }
            if t.hasSuffix("```") { t = String(t.dropLast(3)) }
        }
        return t.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The first top-level JSON object in the text, if any.
    static func jsonObject(in raw: String) -> [String: JSONValue]? {
        let t = stripFences(raw)
        if let obj = decode(t) { return obj }
        guard let start = t.firstIndex(of: "{"), let end = t.lastIndex(of: "}"), start < end else { return nil }
        return decode(String(t[start...end]))
    }

    private static func decode(_ s: String) -> [String: JSONValue]? {
        guard let data = s.data(using: .utf8) else { return nil }
        return (try? JSONDecoder().decode(JSONValue.self, from: data))?.object
    }
}
