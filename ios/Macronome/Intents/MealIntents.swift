import AppIntents
import Foundation

/// A usual meal as Siri and Shortcuts see it.
struct MealEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Usual meal"
    static let defaultQuery = MealQuery()

    var id: String
    var name: String
    var kcal: Double

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)", subtitle: "\(Format.int(kcal)) kcal")
    }
}

struct MealQuery: EntityStringQuery {
    private func all() -> [MealEntity] {
        let ledger = FoodStore.loadLedger()
        return ledger.sortedMeals.map { MealEntity(id: $0.id, name: $0.name, kcal: ledger.preview($0).kcal) }
    }

    func entities(for identifiers: [String]) async throws -> [MealEntity] {
        all().filter { identifiers.contains($0.id) }
    }

    func entities(matching string: String) async throws -> [MealEntity] {
        let q = string.lowercased()
        let ledger = FoodStore.loadLedger()
        return all().filter { e in
            e.name.lowercased().contains(q) || (ledger.meals[e.id]?.aliases.contains { $0.lowercased().contains(q) } ?? false)
        }
    }

    func suggestedEntities() async throws -> [MealEntity] { all() }
}

/// "Log standard breakfast in Macronome". Logs every component without opening the app.
struct LogMealIntent: AppIntent {
    static let title: LocalizedStringResource = "Log a usual meal"
    static let description = IntentDescription("Logs one of your usual meals with its default amounts.")

    @Parameter(title: "Meal") var meal: MealEntity

    static var parameterSummary: some ParameterSummary { Summary("Log \(\.$meal)") }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let store = FoodStore()
        guard let m = store.ledger.meals[meal.id] else {
            return .result(dialog: "I couldn't find \(meal.name).")
        }
        store.log(try Commands.log(m, in: store.ledger, source: InputSource.siri.rawValue))
        let left = store.ledger.status(.kcal, on: store.today).left ?? 0
        return .result(dialog: "Logged \(m.name), \(Format.int(store.ledger.preview(m).kcal)) kcal. \(Format.int(left)) left today.")
    }
}

/// "How much do I have left in Macronome".
struct CaloriesLeftIntent: AppIntent {
    static let title: LocalizedStringResource = "Calories left today"
    static let description = IntentDescription("Says how many calories and grams of protein are left today.")

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let s = DaySnapshot(ledger: FoodStore.loadLedger())
        return .result(dialog: "\(Format.int(s.kcalLeft)) calories and \(Format.int(s.protein.left)) grams of protein left.")
    }
}

struct MacronomeShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: LogMealIntent(), phrases: [
            "Log \(\.$meal) in \(.applicationName)",
            "Had \(\.$meal) in \(.applicationName)",
        ], shortTitle: "Log a meal", systemImageName: "fork.knife")
        AppShortcut(intent: OpenListeningIntent(), phrases: [
            "Log food in \(.applicationName)",
            "Log by voice in \(.applicationName)",
        ], shortTitle: "Log by voice", systemImageName: "mic")
        AppShortcut(intent: CaloriesLeftIntent(), phrases: [
            "How much is left in \(.applicationName)",
            "Calories left in \(.applicationName)",
        ], shortTitle: "Calories left", systemImageName: "chart.pie")
    }
}
