import Foundation

enum Basis: String, Codable, Sendable, CaseIterable {
    case per100g = "100g"
    case serving
}

enum MealSlot: String, Codable, Sendable, CaseIterable, Identifiable {
    case breakfast, lunch, dinner, snack
    var id: String { rawValue }
    var title: String { rawValue.capitalized }

    /// The slot a log made right now most likely belongs to.
    static func guess(at date: Date = Date()) -> MealSlot {
        let h = Calendar.current.component(.hour, from: date)
        switch h {
        case ..<11: return .breakfast
        case 11..<15: return .lunch
        case 15..<17: return .snack
        default: return .dinner
        }
    }
}

/// The macro columns everything sums: kcal, protein, carbs, fat, fiber.
struct Macros: Hashable, Sendable, Codable {
    var kcal: Double = 0
    var protein: Double = 0
    var carbs: Double = 0
    var fat: Double = 0
    var fiber: Double = 0

    static let zero = Macros()
    var netCarbs: Double { carbs - fiber }

    static func + (a: Macros, b: Macros) -> Macros {
        Macros(kcal: a.kcal + b.kcal, protein: a.protein + b.protein, carbs: a.carbs + b.carbs,
               fat: a.fat + b.fat, fiber: a.fiber + b.fiber)
    }
    static func += (a: inout Macros, b: Macros) { a = a + b }

    /// Calories coming from each macro, scaled so the three add up to `kcal`. Used by
    /// the widget ring and the entry breakdown. Carbs count net carbs at 4 and fiber at 2.
    var kcalSplit: (protein: Double, carbs: Double, fat: Double) {
        let p = protein * 4, c = max(0, netCarbs) * 4 + fiber * 2, f = fat * 9
        let sum = p + c + f
        guard sum > 0, kcal > 0 else { return (0, 0, 0) }
        let k = kcal / sum
        return (p * k, c * k, f * k)
    }
}

struct Food: Identifiable, Hashable, Sendable {
    var id: String
    var name: String
    var aliases: [String]
    var basis: Basis
    var servingGrams: Double?
    var servingLabel: String?
    var kcal: Double
    var protein: Double
    var carbs: Double
    var fat: Double
    var fiber: Double?
    var fiberSoluble: Double?
    var fiberInsoluble: Double?
    var micros: [String: Double]
    var source: String?
    var notes: String?
    var createdAt: String?

    /// "per 100 g", "per scoop".
    var perLabel: String { basis == .per100g ? "100 g" : (servingLabel ?? "serving") }
    var macros: Macros {
        Macros(kcal: kcal, protein: protein, carbs: carbs, fat: fat, fiber: fiber ?? 0)
    }
}

struct Entry: Identifiable, Hashable, Sendable {
    var id: String
    var seq: Int
    var foodID: String?
    var label: String
    var qty: Double
    var unit: String
    var grams: Double?
    /// Calories after the fiber adjustment for the current mode.
    var kcal: Double
    var kcalLabel: Double
    var kcalAdjust: Double
    var protein: Double
    var carbs: Double
    var fat: Double
    var fiber: Double?
    var fiberSoluble: Double?
    var fiberInsoluble: Double?
    var micros: [String: Double]
    var eatenOn: String
    var eatenAt: String?
    var meal: MealSlot?
    var source: String?
    var confidence: String?
    var note: String?
    var groupID: String?
    var groupLabel: String?
    var ts: String

    var macros: Macros {
        Macros(kcal: kcal, protein: protein, carbs: carbs, fat: fat, fiber: fiber ?? 0)
    }

    /// "350 g", "2 serv", "1 scoop".
    var amountText: String { Format.amount(qty: qty, unit: unit) }
}

/// A usual meal: named components with default amounts. Each component is logged as
/// its own entry so every ingredient's numbers stay honest.
struct UsualMeal: Identifiable, Hashable, Sendable {
    struct Component: Hashable, Sendable, Codable {
        var foodID: String
        var qty: Double
        var unit: String
    }

    var id: String
    var name: String
    var aliases: [String]
    var slot: MealSlot?
    var components: [Component]
    var note: String?
}

/// Something planned for later today (or another day). Dashed on Today until eaten.
struct PlannedItem: Identifiable, Hashable, Sendable {
    var id: String
    var day: String
    var label: String
    var detail: String?
    var meal: MealSlot?
    var macros: Macros
    /// When the plan came from a usual meal, "Ate it" logs these components.
    var mealID: String?
    var components: [UsualMeal.Component]
}

/// A row in a log list: either one entry or a group logged together.
struct LogGroup: Identifiable, Hashable, Sendable {
    var id: String
    var label: String
    var meal: MealSlot?
    var entries: [Entry]
    var macros: Macros { entries.reduce(.zero) { $0 + $1.macros } }
    var eatenAt: String? { entries.first?.eatenAt }
    /// "Cinnamon crisps · protein · almond milk".
    var subtitle: String {
        entries.count > 1 ? entries.map { Format.shortName($0.label) }.joined(separator: " · ") : entries.first?.amountText ?? ""
    }
}

struct MacroStatus: Hashable, Sendable {
    enum Key: String, Sendable { case kcal, protein, carbs, fat, fiber }
    var key: Key
    var label: String
    var eaten: Double
    var target: Double?
    var isFloor: Bool
    var left: Double? { target.map { $0 - eaten } }
    var fraction: Double {
        guard let t = target, t > 0 else { return 0 }
        return max(0, eaten / t)
    }
}

struct DayTotals: Hashable, Sendable {
    var count: Int
    var macros: Macros
    var kcalLabel: Double
    var kcalAdjust: Double
}

struct Targets: Hashable, Sendable {
    var kcal: Double?
    var protein: Double?
    var carbs: Double?
    var fat: Double?
    var fiber: Double?

    subscript(key: MacroStatus.Key) -> Double? {
        switch key {
        case .kcal: kcal
        case .protein: protein
        case .carbs: carbs
        case .fat: fat
        case .fiber: fiber
        }
    }
}

/// A learned note shown on the Memory screen: profile keys that are not targets,
/// modes or meals.
struct MemoryNote: Identifiable, Hashable, Sendable {
    var id: String { key }
    var key: String
    var value: String
    var updatedAt: String
    var title: String {
        key.replacingOccurrences(of: "_", with: " ").capitalized
    }
}
