import Foundation

/// Parsed items turned into what would be logged: one line per entry, the usual meals
/// they came from, and whatever could not be placed. Macros come from
/// `Ledger.preview`, never from the parser.
struct LogDraft: Sendable {
    struct Line: Identifiable, Hashable, Sendable {
        var id = UUID()
        var food: Food
        var qty: Double
        var unit: String
        /// The usual meal's own amount, when this line is one of its components.
        var defaultQty: Double?
        var defaultUnit: String?
        /// Named in the utterance, as opposed to filled in from the meal.
        var mentioned: Bool
        var alternatives: [String]
        var macros: Macros?
        /// The words used for it ("cookie dough protein"), when they were not a mishearing.
        var spoken: String?

        /// The spoken amount differs from the meal's default ("350 g, was 300").
        var changedFromDefault: Bool {
            guard let defaultQty else { return false }
            return defaultQty != qty || (defaultUnit ?? unit) != unit
        }
    }

    var meals: [UsualMeal] = []
    var lines: [Line] = []
    var estimates: [ParsedItem] = []
    var unresolved: [ParsedItem] = []
    var slot: MealSlot?

    var isEmpty: Bool { lines.isEmpty && estimates.isEmpty }
    var macros: Macros { lines.reduce(.zero) { $0 + ($1.macros ?? .zero) } + estimates.reduce(.zero) { $0 + ($1.estimate ?? .zero) } }

    init(items: [ParsedItem], slot: MealSlot?, ledger: Ledger, readings: [UUID: String] = [:]) {
        self.slot = slot
        var mealLines: Range<Int>?
        for item in items {
            if let mid = item.mealID, let meal = ledger.meals[mid] {
                meals.append(meal)
                let scale = item.qty ?? 1
                let start = lines.count
                for c in meal.components {
                    guard let food = ledger.foods[c.foodID] else { continue }
                    lines.append(Line(food: food, qty: c.qty * scale, unit: c.unit, defaultQty: c.qty * scale,
                                      defaultUnit: c.unit, mentioned: false, alternatives: [],
                                      macros: ledger.preview(food, qty: c.qty * scale, unit: c.unit)))
                }
                mealLines = start..<lines.count
            } else if let fid = item.foodID, let food = ledger.foods[fid] {
                guard let amount = Self.amount(for: food, qty: item.qty, unit: item.unit, ledger: ledger) else {
                    unresolved.append(item)
                    continue
                }
                // A component of the meal just named: override its amount.
                if let range = mealLines, let i = range.first(where: { lines[$0].food.id == fid && !lines[$0].mentioned }) {
                    if item.qty != nil || item.unit != nil {
                        lines[i].qty = amount.qty
                        lines[i].unit = amount.unit
                        lines[i].macros = ledger.preview(food, qty: amount.qty, unit: amount.unit)
                    }
                    lines[i].mentioned = true
                    lines[i].alternatives = item.alternatives
                    continue
                }
                lines.append(Line(food: food, qty: amount.qty, unit: amount.unit, mentioned: true,
                                  alternatives: item.alternatives,
                                  macros: ledger.preview(food, qty: amount.qty, unit: amount.unit),
                                  spoken: readings[item.id] == nil ? item.label : nil))
            } else if item.estimate != nil {
                estimates.append(item)
            } else {
                unresolved.append(item)
            }
        }
        // An amount the engine cannot convert is unresolved rather than guessed.
        lines.removeAll { line in
            if line.macros == nil {
                unresolved.append(ParsedItem(phrase: line.food.name, foodID: line.food.id, qty: line.qty, unit: line.unit))
                return true
            }
            return false
        }
    }

    /// The amount to log when the words gave only part of it.
    static func amount(for food: Food, qty: Double?, unit: String?, ledger: Ledger) -> (qty: Double, unit: String)? {
        func ok(_ q: Double, _ u: String) -> Bool { (try? Ledger.resolveAmount(food, qty: q, unit: u)) != nil }
        let last = ledger.entries.last { $0.foodID == food.id }
        switch (qty, unit) {
        case let (q?, u?):
            return ok(q, u) ? (q, u) : nil
        case let (nil, u?):
            if let last, Ledger.gramUnits.contains(u) == Ledger.gramUnits.contains(last.unit.lowercased()) { return (last.qty, last.unit) }
            return ok(1, u) && !Ledger.gramUnits.contains(u) ? (1, u) : nil
        case let (q?, nil):
            if food.basis == .serving { return (q, food.servingLabel ?? "serving") }
            if q >= 15 { return (q, "g") }
            if food.servingGrams != nil { return (q, food.servingLabel ?? "serving") }
            return nil
        case (nil, nil):
            if let last { return (last.qty, last.unit) }
            if food.basis == .serving || food.servingGrams != nil { return (1, food.servingLabel ?? "serving") }
            return nil
        }
    }

    /// "Potato bowl", "Cookie dough protein and almond milk".
    func label(spoken: [UUID: String] = [:], ledger: Ledger) -> String {
        if !meals.isEmpty {
            return meals.map(\.name).joined(separator: " + ")
        }
        // The same foods as a usual meal: call it that.
        let ids = Set(lines.map(\.food.id))
        if ids.count > 1, let meal = ledger.sortedMeals.first(where: { Set($0.components.map(\.foodID)) == ids }) {
            return meal.name
        }
        let names = lines.map { $0.spoken ?? Self.displayName($0.food.name) } + estimates.map { $0.label ?? $0.phrase }
        switch names.count {
        case 0: return "Entry"
        case 1: return Self.capitalized(names[0])
        case 2: return "\(Self.capitalized(names[0])) and \(names[1])"
        default: return "\(Self.capitalized(names[0])) + \(names.count - 1)"
        }
    }

    /// The slot to log under: what was said, else the meal's own slot when the time of
    /// day agrees with it, else a guess from the clock.
    func resolvedSlot(at date: Date = Date()) -> MealSlot {
        if let slot { return slot }
        let guess = MealSlot.guess(at: date)
        let hour = Calendar.current.component(.hour, from: date)
        if let s = meals.first?.slot {
            switch s {
            case .snack: return .snack
            case .breakfast where hour < 14: return .breakfast
            case .lunch where guess == .lunch || guess == .snack: return .lunch
            case .dinner where hour >= 15: return .dinner
            default: break
            }
        }
        return guess
    }

    /// Entry events for the whole draft, sharing one group so it reads as one row.
    func events(ledger: Ledger, source: String, slot: MealSlot, label: String, day: String = Clock.dayString(),
                at date: Date = Date()) -> [Event] {
        let gid = EventID.make()
        var out: [Event] = []
        let groupLabel = lines.count + estimates.count > 1 || !meals.isEmpty ? label : nil
        for line in lines {
            if let ev = try? Commands.log(line.food, qty: line.qty, unit: line.unit, day: day, meal: slot, source: source,
                                          groupID: gid, groupLabel: groupLabel, at: date) {
                out.append(ev)
            }
        }
        for e in estimates {
            guard let m = e.estimate else { continue }
            out.append(Commands.logEstimate(label: e.label ?? e.phrase, macros: m, day: day, meal: slot, source: source,
                                            confidence: "low", groupID: gid, groupLabel: groupLabel))
        }
        return out
    }

    /// "Farm Girl cinnamon crisps" -> "Cinnamon crisps", "russet potato" -> "Russet potato".
    static func displayName(_ name: String) -> String { capitalized(Format.shortName(name)) }

    static func capitalized(_ s: String) -> String { s.prefix(1).uppercased() + s.dropFirst() }
}
