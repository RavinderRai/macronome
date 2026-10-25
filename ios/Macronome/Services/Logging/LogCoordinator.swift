import Foundation
import Observation

/// Takes what was typed or said and either opens the chat or logs it. Logs never ask
/// first: the local parser runs, a model fills gaps when one is set up, everything
/// resolved is logged as one group, and anything left over gets a small card.
@MainActor
@Observable
final class LogCoordinator {
    /// One instance for Today, the Listening sheet and the edit sheet, which RootView
    /// presents outside Today's environment.
    static let shared = LogCoordinator()

    /// Words that could not be matched, offered as "Add as a new food" or "Ask in chat".
    struct Leftover: Identifiable, Equatable {
        let id = UUID()
        var text: String
        var phrases: [String]
    }

    /// What the card and the edit sheet need to explain a log after the fact.
    struct Context: Equatable {
        var heard: String
        var source: InputSource
        /// "Read it as Evening bowl."
        var reading: String?
        /// Entry food id -> other foods the words could have meant.
        var alternatives: [String: [String]] = [:]
    }

    private(set) var isWorking = false
    var leftover: Leftover?
    private(set) var contexts: [String: Context] = [:]

    let interpreter = LocalLogInterpreter()

    func context(for groupID: String) -> Context? { contexts[groupID] }

    func submit(_ raw: String, source: InputSource, store: FoodStore, router: Router, models: ModelRouter) async {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        leftover = nil
        if LogIntent.of(text) == .question {
            router.sheet = .chat(prompt: text)
            return
        }

        let ledger = store.ledger
        var parse = interpreter.parse(text, ledger: ledger)
        if !parse.unresolved.isEmpty, let model = models.interpreter() {
            isWorking = true
            let gaps = parse.unresolved.map(\.phrase).joined(separator: ", ")
            if let extra = try? await model.interpret(gaps, ledger: ledger) {
                let valid = extra.filter { item in
                    item.foodID.map { ledger.foods[$0] != nil } ?? item.mealID.map { ledger.meals[$0] != nil } ?? (item.estimate != nil)
                }
                if !valid.isEmpty {
                    parse.items.removeAll { !$0.isResolved }
                    parse.items += valid
                    parse.items += extra.filter { !$0.isResolved }
                }
            }
            isWorking = false
        }

        let draft = LogDraft(items: parse.items, slot: parse.slot, ledger: ledger, readings: parse.readings)
        log(draft, parse: parse, heard: text, source: source, store: store)
        let missing = draft.unresolved.map { $0.label ?? $0.phrase }.filter { !$0.isEmpty }
        if !missing.isEmpty {
            leftover = Leftover(text: text, phrases: missing)
        } else if draft.isEmpty {
            leftover = Leftover(text: text, phrases: [text])
        }
    }

    /// A usual-meal chip: logged straight away, like any other log.
    func logMeal(_ meal: UsualMeal, store: FoodStore) {
        leftover = nil
        let draft = LogDraft(items: [ParsedItem(phrase: meal.name, mealID: meal.id)], slot: nil, ledger: store.ledger)
        log(draft, parse: nil, heard: meal.name, source: .text, store: store)
    }

    private func log(_ draft: LogDraft, parse: LogParse?, heard: String, source: InputSource, store: FoodStore) {
        guard !draft.isEmpty else { return }
        let ledger = store.ledger
        let today = Clock.dayString()
        let plan = matchingPlan(draft, ledger: ledger, day: today)
        let slot = draft.slot ?? plan?.meal ?? draft.resolvedSlot()
        let label = draft.label(ledger: ledger)
        let events = draft.events(ledger: ledger, source: source.rawValue, slot: slot, label: label, day: today)
        guard !events.isEmpty else { return }
        store.log(events, replacing: plan)
        let gid = events.first?.string("group_id") ?? events.first?.id ?? ""
        var alternatives: [String: [String]] = [:]
        for line in draft.lines where !line.alternatives.isEmpty { alternatives[line.food.id] = line.alternatives }
        let readings = (parse?.items ?? []).compactMap { item in
            parse?.readings[item.id].map { (heard: item.label ?? item.phrase, name: $0) }
        }
        contexts[gid] = Context(heard: heard, source: source,
                                reading: readings.isEmpty ? nil : Self.describe(readings),
                                alternatives: alternatives)
    }

    /// A plan for today that this log fulfils: the same usual meal, or the same name.
    func matchingPlan(_ draft: LogDraft, ledger: Ledger, day: String) -> PlannedItem? {
        let plans = ledger.plans(on: day)
        if draft.meals.count == 1, let meal = draft.meals.first {
            return plans.first { $0.mealID == meal.id || Ledger.norm($0.label) == Ledger.norm(meal.name) }
        }
        return nil
    }

    /// "Read “full bold of serial” as Evening bowl."
    static func describe(_ readings: [(heard: String, name: String)]) -> String {
        let parts = readings.map { "“\($0.heard)” as \(LogDraft.displayName($0.name))" }
        return "Read " + parts.joined(separator: ", ") + "."
    }

    func forget(_ groupID: String) { contexts[groupID] = nil }
}
