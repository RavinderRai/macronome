import Foundation

/// An editable food before it is saved: filled by hand, from a label photo, or from
/// the pantry scan. Turned into a food_add event by `Commands.addFood`.
struct FoodDraft: Hashable, Identifiable {
    var id = UUID()
    var name = ""
    var aliases = ""
    var basis: Basis = .serving
    var servingGrams: Double?
    var servingLabel: String? = "serving"
    var kcal: Double?
    var protein: Double?
    var carbs: Double?
    var fat: Double?
    var fiber: Double?
    var fiberSoluble: Double?
    var fiberInsoluble: Double?
    var micros: [String: Double] = [:]
    var source = "manual"
    var notes: String?
    /// Text the label reader saw, kept so mistakes are visible.
    var rawText: String?
    /// Fields the reader was unsure of, highlighted on the form.
    var uncertain: Set<String> = []

    var isComplete: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && kcal != nil && protein != nil && carbs != nil && fat != nil
    }

    func food(id: String = EventID.make()) -> Food {
        Food(id: id, name: name.trimmingCharacters(in: .whitespaces),
             aliases: aliases.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty },
             basis: basis, servingGrams: servingGrams, servingLabel: servingLabel, kcal: kcal ?? 0,
             protein: protein ?? 0, carbs: carbs ?? 0, fat: fat ?? 0, fiber: fiber, fiberSoluble: fiberSoluble,
             fiberInsoluble: fiberInsoluble, micros: micros, source: source, notes: notes, createdAt: nil)
    }

    init() {}

    init(_ food: Food) {
        name = food.name
        aliases = food.aliases.joined(separator: ", ")
        basis = food.basis
        servingGrams = food.servingGrams
        servingLabel = food.servingLabel
        kcal = food.kcal
        protein = food.protein
        carbs = food.carbs
        fat = food.fat
        fiber = food.fiber
        fiberSoluble = food.fiberSoluble
        fiberInsoluble = food.fiberInsoluble
        micros = food.micros
        source = food.source ?? "manual"
        notes = food.notes
    }

    /// The label's own arithmetic: printed kcal against P*4+C*4+F*9 and that minus
    /// twice the fiber. nil when it is consistent with either.
    var labelArithmeticWarning: String? {
        guard let kcal, let p = protein, let c = carbs, let f = fat else { return nil }
        let a4 = p * 4 + c * 4 + f * 9
        let a2 = a4 - 2 * (fiber ?? 0)
        let tolerance = max(15, kcal * 0.15)
        if abs(kcal - a4) <= tolerance || abs(kcal - a2) <= tolerance { return nil }
        return "The label says \(Format.int(kcal)) kcal but its macros add up to \(Format.int(a2))–\(Format.int(a4))."
    }
}
