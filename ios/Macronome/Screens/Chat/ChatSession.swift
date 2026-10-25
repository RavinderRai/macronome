import Foundation
import Observation

/// Today's conversation, kept as JSON in Application Support so closing the sheet
/// does not lose it. One file per day; "New chat" clears today's.
@MainActor
@Observable
final class ChatSession {
    struct Snapshot: Codable {
        var day: String
        var messages: [ChatMessage] = []
        /// message id -> chosen option id.
        var selection: [UUID: UUID] = [:]
        /// option id -> plan event id, once "Add to today" was tapped.
        var planned: [UUID: String] = [:]
        var logged: Set<UUID> = []
    }

    private(set) var snapshot: Snapshot
    var busy = false
    var error: String?
    @ObservationIgnored private let directory: URL

    var messages: [ChatMessage] { snapshot.messages }

    init(day: String = Clock.dayString(), directory: URL = ChatSession.defaultDirectory) {
        self.directory = directory
        let url = directory.appendingPathComponent("\(day).json")
        if let data = try? Data(contentsOf: url), let s = try? JSONDecoder().decode(Snapshot.self, from: data), s.day == day {
            snapshot = s
        } else {
            snapshot = Snapshot(day: day)
        }
    }

    static var defaultDirectory: URL {
        let fm = FileManager.default
        let base = (try? fm.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true))
            ?? fm.temporaryDirectory
        return base.appendingPathComponent("Chat", isDirectory: true)
    }

    private func save() {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try JSONEncoder().encode(snapshot).write(to: directory.appendingPathComponent("\(snapshot.day).json"), options: .atomic)
        } catch {
            // A lost transcript is not worth interrupting the chat for.
        }
    }

    func reset() {
        snapshot = Snapshot(day: snapshot.day)
        error = nil
        save()
    }

    // MARK: options

    func selected(in message: ChatMessage) -> MealOption? {
        let id = snapshot.selection[message.id]
        return message.options.first { $0.id == id } ?? message.options.first
    }

    func select(_ option: MealOption, in message: ChatMessage) {
        snapshot.selection[message.id] = option.id
        save()
    }

    func planID(for option: MealOption) -> String? { snapshot.planned[option.id] }
    func isLogged(_ option: MealOption) -> Bool { snapshot.logged.contains(option.id) }

    /// "Add to today": a dashed planned entry with macros computed from the ledger.
    func plan(_ option: MealOption, store: FoodStore) {
        guard planID(for: option) == nil, !isLogged(option) else { return }
        let ledger = store.ledger
        let event = Commands.plan(label: option.title, detail: option.detail,
                                  macros: ChatReplyParser.macros(option.components, ledger: ledger),
                                  meal: option.slot, mealID: option.mealID, components: option.components)
        store.append(event)
        snapshot.planned[option.id] = event.id
        save()
    }

    /// "Log it": every component as its own entry, one group named after the option.
    /// Replaces the plan when the option was planned first.
    func log(_ option: MealOption, store: FoodStore) throws {
        guard !isLogged(option) else { return }
        let ledger = store.ledger
        let gid = EventID.make()
        let slot = option.slot ?? option.mealID.flatMap { ledger.meals[$0]?.slot } ?? MealSlot.guess()
        let events = try option.components.compactMap { c -> Event? in
            guard let food = ledger.foods[c.foodID] else { return nil }
            return try Commands.log(food, qty: c.qty, unit: c.unit, meal: slot, source: "chat",
                                    groupID: gid, groupLabel: option.title)
        }
        guard !events.isEmpty else { return }
        let plan = planID(for: option).flatMap { ledger.plans[$0] }
        store.log(events, replacing: plan)
        snapshot.logged.insert(option.id)
        snapshot.planned[option.id] = nil
        save()
    }

    // MARK: sending

    func send(_ text: String, models: ModelRouter, store: FoodStore) async {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, !busy else { return }
        snapshot.messages.append(ChatMessage(role: .user, text: t))
        save()
        await answer(models: models, store: store)
    }

    /// Ask again after a failure, without repeating the user's message.
    func retry(models: ModelRouter, store: FoodStore) async {
        guard snapshot.messages.last?.role == .user else { return }
        await answer(models: models, store: store)
    }

    private func answer(models: ModelRouter, store: FoodStore) async {
        busy = true
        error = nil
        defer { busy = false }
        do {
            let reply = try await models.reply(to: snapshot.messages, ledger: store.ledger)
            snapshot.messages.append(reply)
            save()
        } catch {
            self.error = error.localizedDescription
        }
    }
}
