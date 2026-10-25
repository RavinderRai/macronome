import Foundation

// Contracts between the logging flow, the chat and the model layer. Implementations
// live in Services/AI; screens only talk to these types.

/// How a log arrived, written to the entry's `source`.
enum InputSource: String, Sendable {
    case text, voice, photo, label, widget, siri
}

/// One thing the user said they ate, before it is logged.
struct ParsedItem: Hashable, Sendable, Identifiable {
    var id = UUID()
    /// What was heard, e.g. "a hundred grams of cauliflower".
    var phrase: String
    var foodID: String?
    var mealID: String?
    var qty: Double?
    var unit: String?
    /// A one-off estimate with no stored food (restaurant, plate).
    var estimate: Macros?
    var label: String?
    /// Other foods the phrase could mean, when the match was not unique.
    var alternatives: [String] = []

    var isResolved: Bool { foodID != nil || mealID != nil || estimate != nil }
}

/// Turns free text into items against the user's own library.
protocol LogInterpreter: Sendable {
    func interpret(_ text: String, ledger: Ledger) async throws -> [ParsedItem]
}

enum ChatRole: String, Codable, Sendable { case user, assistant, system }

struct ChatMessage: Identifiable, Hashable, Codable, Sendable {
    var id = UUID()
    var role: ChatRole
    var text: String
    /// Meal options the assistant proposed, shown as cards under the message.
    var options: [MealOption] = []
    var date = Date()
}

/// A meal idea from the chat that can be planned or logged in one tap.
struct MealOption: Identifiable, Hashable, Codable, Sendable {
    var id = UUID()
    var title: String
    var detail: String?
    var mealID: String?
    var components: [UsualMeal.Component] = []
    var kcal: Double
    var protein: Double
    var carbs: Double = 0
    var fat: Double = 0
    var slot: MealSlot?

    var macros: Macros { Macros(kcal: kcal, protein: protein, carbs: carbs, fat: fat) }
}

/// What the command bar decided to do with an input.
enum Intent: Sendable, Equatable {
    case log
    case question
}
