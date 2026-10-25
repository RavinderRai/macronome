import Foundation

/// One line of the append-only log. Same shape as food-log's `events.jsonl`.
///
/// Types food-log already writes: food_add, food_update, food_delete, entry_add,
/// entry_delete, profile_set, day_target, day_note.
/// Types added by the app (fl.py skips them): meal_set, meal_delete, plan_add,
/// plan_delete, memory_delete. entry_add also gains optional group_id / group_label
/// so a meal logged in one go shows as one row.
struct Event: Codable, Hashable, Sendable, Identifiable {
    var fields: [String: JSONValue]

    init(_ fields: [String: JSONValue]) { self.fields = fields }

    init(from decoder: Decoder) throws {
        fields = try decoder.singleValueContainer().decode([String: JSONValue].self)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(fields)
    }

    subscript(key: String) -> JSONValue? {
        get { fields[key] }
        set { fields[key] = newValue }
    }

    var id: String { fields["id"]?.string ?? "" }
    var ts: String { fields["ts"]?.string ?? "" }
    var type: String { fields["type"]?.string ?? "" }

    func string(_ key: String) -> String? { fields[key]?.string }
    func double(_ key: String) -> Double? { fields[key]?.double }

    static func new(_ type: String, _ fields: [String: JSONValue] = [:]) -> Event {
        var f = fields
        f["type"] = .string(type)
        f["id"] = f["id"] ?? .string(EventID.make())
        f["ts"] = f["ts"] ?? .string(Clock.nowISO())
        return Event(f)
    }
}

enum EventID {
    /// Six hex characters, like `secrets.token_hex(3)` in fl.py.
    static func make() -> String {
        (0..<3).map { _ in String(format: "%02x", UInt8.random(in: 0...255)) }.joined()
    }
}

enum EventCodec {
    static func decodeLines(_ data: Data) -> [Event] {
        guard let text = String(data: data, encoding: .utf8) else { return [] }
        var seen = Set<String>()
        var out: [Event] = []
        let decoder = JSONDecoder()
        for raw in text.split(whereSeparator: \.isNewline) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("<<<<<<<") || line.hasPrefix(">>>>>>>")
                || line.hasPrefix("=======") { continue }
            guard let ev = try? decoder.decode(Event.self, from: Data(line.utf8)) else { continue }
            if !ev.id.isEmpty {
                if seen.contains(ev.id) { continue }
                seen.insert(ev.id)
            }
            out.append(ev)
        }
        // Stable sort by timestamp, matching fl.py's events.sort(key=ts).
        return out.enumerated().sorted { a, b in
            a.element.ts == b.element.ts ? a.offset < b.offset : a.element.ts < b.element.ts
        }.map(\.element)
    }

    static func encodeLine(_ event: Event) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let data = (try? encoder.encode(event)) ?? Data()
        return String(data: data, encoding: .utf8) ?? "{}"
    }
}

enum Clock {
    static func nowISO(_ date: Date = Date()) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        f.timeZone = .current
        return f.string(from: date)
    }

    static func dayString(_ date: Date = Date()) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    static func date(fromDay day: String) -> Date? {
        let parts = day.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return Calendar.current.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }

    static func addDays(_ day: String, _ n: Int) -> String {
        guard let d = date(fromDay: day),
              let moved = Calendar.current.date(byAdding: .day, value: n, to: d) else { return day }
        return dayString(moved)
    }

    static func parseISO(_ s: String?) -> Date? {
        guard let s else { return nil }
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        if let d = f.date(from: s) { return d }
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.date(from: s)
    }
}
