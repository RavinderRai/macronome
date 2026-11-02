import Foundation

/// What a chat reply shows under its text. Every number on a card was computed by the
/// app when the tool ran, and is kept as it was then so old cards read the same.
enum ChatCard: Codable, Hashable, Sendable, Identifiable {
    case logged(LogCard)
    case options(OptionsCard)
    case targets(TargetsCard)
    case remembered(RememberedCard)

    var id: UUID {
        switch self {
        case .logged(let c): c.id
        case .options(let c): c.id
        case .targets(let c): c.id
        case .remembered(let c): c.id
        }
    }
}

/// What's left, and what's left once the held-back meal (the evening bowl) is counted.
struct StatusLine: Codable, Hashable, Sendable {
    var kcal: Double?
    var protein: Double?
    var carbs: Double?
    var fat: Double?
    var carbsLabel = "C"
    /// "Evening bowl", when one is held back.
    var holdBack: String?
    var afterHoldBackKcal: Double?
    var afterHoldBackProtein: Double?
}

struct LogCard: Codable, Hashable, Sendable {
    struct Row: Codable, Hashable, Sendable {
        var label: String
        var amount: String?
        var kcal: Double
        var estimate = false
    }
    struct DayGroup: Codable, Hashable, Sendable {
        var day: String
        /// "Today", "Sat 31 Oct".
        var title: String
        var slot: String?
        var name: String
        var rows: [Row]
        var kcal: Double { rows.reduce(0) { $0 + $1.kcal } }
    }

    var id = UUID()
    var groups: [DayGroup]
    var entryIDs: [String]
    /// "I took “pull a ball” to mean your full bowl."
    var assumption: String?
    var status: StatusLine
    /// Entries removed by a correction, put back if this card is undone.
    var replacedEventIDs: [String] = []
}

struct OptionsCard: Codable, Hashable, Sendable {
    struct Row: Codable, Hashable, Sendable {
        var label: String
        var kcal: Double
        var protein: Double
        /// Budget minus kcal: positive is spare, negative is over.
        var spare: Double?
        var hitsProtein: Bool
    }
    var id = UUID()
    /// Column header, "Dinner" or "Bread".
    var title: String
    var rows: [Row]
    var budgetKcal: Double?
    var budgetProtein: Double?
    var holdBack: String?
    var holdBackKcal: Double?
    var holdBackProtein: Double?
}

struct TargetsCard: Codable, Hashable, Sendable {
    struct Row: Codable, Hashable, Sendable {
        var label: String
        var was: Double?
        var now: Double?
        var unit: String
    }
    var id = UUID()
    var rows: [Row]
    var eventIDs: [String]
    /// The old values, as profile events, to restore on Undo.
    var previous: [String: String]
}

struct RememberedCard: Codable, Hashable, Sendable {
    var id = UUID()
    var key: String
    var kind: String
    var text: String
}

extension ChatCard {
    /// The events that reverse what the card's tool wrote: a log (putting back what it
    /// corrected), a target change, or a remembered item. Options wrote nothing.
    func undoEvents(in ledger: Ledger) -> [Event] {
        switch self {
        case .logged(let c):
            var events = c.entryIDs.map(Commands.deleteEntry)
            let replaced = Set(c.replacedEventIDs)
            for ev in ledger.events where ev.type == "entry_add" && replaced.contains(ev.id) {
                var f = ev.fields
                f["id"] = nil
                f["ts"] = nil
                events.append(Event.new("entry_add", f))
            }
            return events
        case .targets(let c):
            return c.previous.sorted { $0.key < $1.key }.map { Commands.setProfile($0.key, $0.value) }
        case .remembered(let c):
            return [Commands.forgetMemory(c.key)]
        case .options:
            return []
        }
    }

    /// The card in words, sent back to the model with later turns so "had the second
    /// one" has something to point at.
    var summary: String {
        switch self {
        case .logged(let c):
            let parts = c.groups.map { g in
                "\(g.title) \(g.slot ?? ""): \(g.name) (\(g.rows.map { "\($0.label) \($0.amount ?? "")" }.joined(separator: ", ")))"
            }
            return "[Logged: " + parts.joined(separator: "; ") + "]"
        case .options(let c):
            let rows = c.rows.enumerated().map { i, r in
                "\(i + 1). \(r.label) \(Format.int(r.kcal)) kcal \(Format.int(r.protein)) g P"
            }
            return "[Options shown (\(c.title)): " + rows.joined(separator: "; ") + "]"
        case .targets(let c):
            return "[Targets set: " + c.rows.map { "\($0.label) \(Format.int($0.now))" }.joined(separator: ", ") + "]"
        case .remembered(let c):
            return "[Remembered (\(c.kind)): \(c.text)]"
        }
    }
}
