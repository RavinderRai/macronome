import Foundation

/// The state you get by replaying the event log, the Swift twin of `project()` in
/// food-log/fl.py. Rebuilt from scratch on every change; a year of logging is a few
/// thousand events, which replays in milliseconds.
struct Ledger: Sendable {
    static let defaultFiberMode = "auto"
    static let fiberModes: [(key: String, summary: String)] = [
        ("auto", "Trust each label: deduct only when its calories counted fiber at 4 kcal/g"),
        ("label", "Never deduct, calories exactly as printed"),
        ("half", "Always deduct 2 kcal per gram of fiber"),
        ("net", "Always deduct 4 kcal per gram, net-carb style"),
        ("split", "Insoluble at 0 and soluble at 2 kcal/g"),
    ]

    private(set) var events: [Event] = []
    private(set) var foods: [String: Food] = [:]
    private(set) var entries: [Entry] = []
    private(set) var profile: [String: String] = [:]
    private(set) var profileUpdatedAt: [String: String] = [:]
    private(set) var dayTargets: [String: [String: Double]] = [:]
    private(set) var dayNotes: [String: String] = [:]
    private(set) var meals: [String: UsualMeal] = [:]
    private(set) var plans: [String: PlannedItem] = [:]
    private(set) var deletedMemory: Set<String> = []

    init(events: [Event] = []) {
        self.events = events
        replay()
    }

    var fiberMode: String {
        let mode = profile["fiber_mode"] ?? Self.defaultFiberMode
        return Self.fiberModes.contains { $0.key == mode } ? mode : Self.defaultFiberMode
    }

    /// "net" shows carbs minus fiber; the Python default is "total".
    var carbMode: String { profile["carb_mode"] == "net" ? "net" : "total" }

    // MARK: replay

    private mutating func replay() {
        // fiber_mode is read from the whole log first, exactly like fl.py, so a mode
        // switch re-scores every day already logged.
        var mode = Self.defaultFiberMode
        for ev in events where ev.type == "profile_set" && ev.string("key") == "fiber_mode" {
            if let v = ev.string("value"), Self.fiberModes.contains(where: { $0.key == v }) { mode = v }
        }

        var seq = 0
        var entryIndex: [String: Int] = [:]
        var list: [Entry?] = []
        for ev in events {
            switch ev.type {
            case "food_add":
                foods[ev.id] = Self.food(from: ev.fields, id: ev.id, createdAt: ev.ts)
            case "food_update":
                guard let target = ev.string("target"), var food = foods[target],
                      let fields = ev["fields"]?.object else { break }
                var merged = Self.foodFields(food)
                for (k, v) in fields where Self.foodFieldNames.contains(k) { merged[k] = v }
                food = Self.food(from: merged, id: food.id, createdAt: food.createdAt)
                foods[target] = food
            case "food_delete":
                if let t = ev.string("target") { foods[t] = nil }
            case "entry_add":
                seq += 1
                let e = Self.entry(from: ev, seq: seq, mode: mode)
                if let i = entryIndex[e.id] { list[i] = e } else {
                    entryIndex[e.id] = list.count
                    list.append(e)
                }
            case "entry_delete":
                if let t = ev.string("target"), let i = entryIndex[t] {
                    list[i] = nil
                    entryIndex[t] = nil
                }
            case "profile_set":
                if let k = ev.string("key") {
                    profile[k] = ev.string("value") ?? ev.double("value").map { String($0) } ?? ""
                    profileUpdatedAt[k] = ev.ts
                    deletedMemory.remove(k)
                }
            case "memory_delete":
                if let k = ev.string("key") { deletedMemory.insert(k) }
            case "day_target":
                if let d = ev.string("day"), let k = ev.string("key"), let v = ev.double("value") {
                    dayTargets[d, default: [:]][k] = v
                }
            case "day_note":
                if let d = ev.string("day") { dayNotes[d] = ev.string("note") ?? "" }
            case "meal_set":
                if let m = Self.meal(from: ev) { meals[m.id] = m }
            case "meal_delete":
                if let t = ev.string("target") { meals[t] = nil }
            case "plan_add":
                if let p = Self.plan(from: ev) { plans[p.id] = p }
            case "plan_delete":
                if let t = ev.string("target") { plans[t] = nil }
            default:
                break
            }
        }
        entries = list.compactMap { $0 }
    }

    // MARK: fiber

    /// Calories to remove so fiber counts at ~2 kcal/g rather than 4. Port of
    /// `fiber_adjustment` in fl.py; see food-log/CLAUDE.md for why "auto" exists.
    static func fiberAdjustment(fiber: Double?, soluble: Double?, insoluble: Double?, mode: String,
                                kcal: Double?, protein: Double?, carbs: Double?, fat: Double?) -> Double {
        let sol = soluble ?? 0, insol = insoluble ?? 0
        let total = fiber ?? (sol + insol)
        switch mode {
        case "auto":
            guard total != 0, let kcal, let protein, let carbs, let fat else { return 0 }
            let atwater4 = 4 * protein + 4 * carbs + 9 * fat
            if kcal < atwater4 - total { return 0 }
            return round2(2 * total)
        case "label": return 0
        case "half": return round2(2 * total)
        case "net": return round2(4 * total)
        default:
            let unspecified = max(0, total - sol - insol)
            return round2(4 * insol + 2 * (sol + unspecified))
        }
    }

    /// The same day scored under every convention, for the fiber setting.
    func kcalUnderEachMode(day: String) -> [(mode: String, kcal: Double)] {
        let rows = entries.filter { $0.eatenOn == day }
        return Self.fiberModes.map { mode in
            let total = rows.reduce(0.0) { sum, r in
                let adj = Self.fiberAdjustment(fiber: r.fiber, soluble: r.fiberSoluble, insoluble: r.fiberInsoluble,
                                               mode: mode.key, kcal: r.kcalLabel, protein: r.protein,
                                               carbs: r.carbs, fat: r.fat)
                return sum + max(0, r.kcalLabel - adj)
            }
            return (mode.key, total)
        }
    }

    // MARK: days

    func entries(on day: String) -> [Entry] {
        entries.filter { $0.eatenOn == day }.sorted {
            ($0.eatenAt ?? "", $0.seq) < ($1.eatenAt ?? "", $1.seq)
        }
    }

    func totals(on day: String) -> DayTotals { totals(from: day, to: day) }

    func totals(from start: String, to end: String) -> DayTotals {
        let rows = entries.filter { $0.eatenOn >= start && $0.eatenOn <= end }
        return DayTotals(count: rows.count, macros: rows.reduce(.zero) { $0 + $1.macros },
                         kcalLabel: rows.reduce(0) { $0 + $1.kcalLabel },
                         kcalAdjust: rows.reduce(0) { $0 + $1.kcalAdjust })
    }

    func micros(on day: String) -> [String: Double] {
        var out: [String: Double] = [:]
        for e in entries where e.eatenOn == day {
            for (k, v) in e.micros { out[k, default: 0] += v }
        }
        return out
    }

    var standingTargets: Targets {
        Targets(kcal: Double(profile["target_kcal"] ?? ""), protein: Double(profile["target_protein"] ?? ""),
                carbs: Double(profile["target_carbs"] ?? ""), fat: Double(profile["target_fat"] ?? ""),
                fiber: Double(profile["target_fiber"] ?? ""))
    }

    /// Standing targets with any one-day override applied.
    func targets(on day: String) -> Targets {
        var t = standingTargets
        let o = dayTargets[day] ?? [:]
        t.kcal = o["kcal"] ?? t.kcal
        t.protein = o["protein"] ?? t.protein
        t.carbs = o["carbs"] ?? t.carbs
        t.fat = o["fat"] ?? t.fat
        t.fiber = o["fiber"] ?? t.fiber
        return t
    }

    func hasOverride(on day: String) -> Bool { !(dayTargets[day] ?? [:]).isEmpty }

    /// Port of `macro_status`: in net mode carbs are carbs minus fiber and the carb
    /// target gives back the calories the fiber deduction already removed, so hitting
    /// protein, fat and net carbs means hitting calories. Fiber is a floor.
    func macroStatus(on day: String, extra: Macros = .zero) -> [MacroStatus] {
        let totals = totals(on: day)
        let m = totals.macros + extra
        let t = targets(on: day)
        let net = carbMode == "net"
        return [MacroStatus.Key.kcal, .protein, .carbs, .fat, .fiber].map { key in
            var eaten: Double
            var target = t[key]
            var label = key.rawValue
            switch key {
            case .kcal: eaten = m.kcal; label = "Calories"
            case .protein: eaten = m.protein; label = "Protein"
            case .carbs:
                eaten = net ? m.netCarbs : m.carbs
                label = net ? "Net carbs" : "Carbs"
                if net, let tt = target { target = tt - totals.kcalAdjust / 4 }
            case .fat: eaten = m.fat; label = "Fat"
            case .fiber: eaten = m.fiber; label = "Fiber"
            }
            return MacroStatus(key: key, label: label, eaten: eaten, target: target, isFloor: key == .fiber)
        }
    }

    func status(_ key: MacroStatus.Key, on day: String) -> MacroStatus {
        macroStatus(on: day).first { $0.key == key }!
    }

    func plans(on day: String) -> [PlannedItem] {
        plans.values.filter { $0.day == day }.sorted {
            (Self.slotOrder($0.meal), $0.id) < (Self.slotOrder($1.meal), $1.id)
        }
    }

    func plannedMacros(on day: String) -> Macros { plans(on: day).reduce(.zero) { $0 + $1.macros } }

    /// Days with at least one entry, newest first.
    var loggedDays: [String] { Array(Set(entries.map(\.eatenOn))).sorted(by: >) }

    var firstDay: String? { entries.map(\.eatenOn).min() }

    /// "Day 42": days since the first log, counting that day as 1.
    func dayNumber(_ day: String) -> Int? {
        guard let first = firstDay, let a = Clock.date(fromDay: first), let b = Clock.date(fromDay: day) else { return nil }
        let days = Calendar.current.dateComponents([.day], from: a, to: b).day ?? 0
        return days >= 0 ? days + 1 : nil
    }

    /// The leading number of the calorie_bank profile note, e.g. "15 - built ...".
    var bank: Double? {
        guard let raw = profile["calorie_bank"] else { return nil }
        let scanner = Scanner(string: raw)
        return scanner.scanDouble()
    }

    // MARK: groups

    static func slotOrder(_ s: MealSlot?) -> Int {
        switch s {
        case .breakfast: 0
        case .lunch: 1
        case .snack: 2
        case .dinner: 3
        case nil: 4
        }
    }

    /// Entries for a day folded into rows. Entries that share a group_id are one row;
    /// older entries without one are folded when they were logged together (same
    /// meal, within three minutes) so imported history reads the same way.
    func groups(on day: String) -> [LogGroup] {
        var out: [LogGroup] = []
        for e in entries(on: day) {
            if let gid = e.groupID {
                if let i = out.firstIndex(where: { $0.id == gid }) { out[i].entries.append(e); continue }
                out.append(LogGroup(id: gid, label: e.groupLabel ?? e.label, meal: e.meal, entries: [e]))
                continue
            }
            if let last = out.last, last.entries.allSatisfy({ $0.groupID == nil }), last.meal == e.meal,
               let a = Clock.parseISO(last.entries.last?.eatenAt), let b = Clock.parseISO(e.eatenAt),
               abs(b.timeIntervalSince(a)) <= 180 {
                out[out.count - 1].entries.append(e)
                continue
            }
            out.append(LogGroup(id: e.id, label: e.label, meal: e.meal, entries: [e]))
        }
        return out.map { g in
            var g = g
            if g.entries.count > 1, g.entries.first?.groupLabel == nil { g.label = guessMealName(g.entries) }
            return g
        }
    }

    private func guessMealName(_ entries: [Entry]) -> String {
        let ids = Set(entries.compactMap(\.foodID))
        let best = meals.values.max { a, b in
            overlap(a, ids) < overlap(b, ids)
        }
        if let best, overlap(best, ids) >= max(2, best.components.count - 1) { return best.name }
        let first = Format.shortName(entries[0].label)
        return entries.count > 1 ? "\(first) + \(entries.count - 1)" : first
    }

    private func overlap(_ meal: UsualMeal, _ ids: Set<String>) -> Int {
        meal.components.filter { ids.contains($0.foodID) }.count
    }

    func group(id: String) -> LogGroup? {
        guard let e = entries.first(where: { $0.id == id || $0.groupID == id }) else { return nil }
        return groups(on: e.eatenOn).first { g in g.id == id || g.entries.contains { $0.id == id } }
    }

    /// The most recent groups logged, newest first; drives the usual-meal chips.
    var lastGroup: LogGroup? {
        guard let last = entries.max(by: { $0.seq < $1.seq }) else { return nil }
        return group(id: last.groupID ?? last.id)
    }

    // MARK: memory

    static let structuralKeys: Set<String> = ["fiber_mode", "carb_mode", "calorie_bank"]

    var memoryNotes: [MemoryNote] {
        profile.compactMap { key, value in
            if key.hasPrefix("target_") || key.hasPrefix("meal_") || Self.structuralKeys.contains(key)
                || deletedMemory.contains(key) { return nil }
            return MemoryNote(key: key, value: value, updatedAt: profileUpdatedAt[key] ?? "")
        }.sorted { $0.updatedAt > $1.updatedAt }
    }

    // MARK: foods

    var sortedFoods: [Food] { foods.values.sorted { $0.name.lowercased() < $1.name.lowercased() } }
    var sortedMeals: [UsualMeal] { meals.values.sorted { $0.name < $1.name } }

    enum FoodMatch: Equatable {
        case found(Food)
        case ambiguous([Food])
        case none
    }

    /// Port of `find_food`: exact name, then a unique alias, then a unique partial
    /// name, then an id prefix.
    func findFood(_ query: String) -> FoodMatch {
        let q = Self.norm(query)
        guard !q.isEmpty else { return .none }
        let rows = Array(foods.values)
        let byID = rows.filter { $0.id == q || $0.id.hasPrefix(q) }
        let exact = rows.filter { Self.norm($0.name) == q }
        if exact.count == 1 { return .found(exact[0]) }
        let alias = rows.filter { $0.aliases.map(Self.norm).contains(q) }
        if alias.count == 1 { return .found(alias[0]) }
        let partial = rows.filter { Self.norm($0.name).contains(q) }
        if partial.count == 1 { return .found(partial[0]) }
        if byID.count == 1 { return .found(byID[0]) }
        let candidates = !exact.isEmpty ? exact : !alias.isEmpty ? alias : !partial.isEmpty ? partial : byID
        return candidates.isEmpty ? .none : .ambiguous(candidates.sorted { $0.name < $1.name })
    }

    func findMeal(_ query: String) -> UsualMeal? {
        let q = Self.norm(query)
        guard !q.isEmpty else { return nil }
        return meals.values.first { Self.norm($0.name) == q || $0.aliases.map(Self.norm).contains(q) }
    }

    /// Foods and meals whose name or aliases contain the query, for search fields.
    func searchFoods(_ query: String) -> [Food] {
        let q = Self.norm(query)
        guard !q.isEmpty else { return sortedFoods }
        return sortedFoods.filter { Self.norm($0.name).contains(q) || $0.aliases.contains { Self.norm($0).contains(q) } }
    }

    static let gramUnits: Set<String> = ["g", "gram", "grams", "ml", "milliliter", "milliliters"]
    static let servingUnits: Set<String> = [
        "serving", "servings", "serv", "scoop", "scoops", "slice", "slices", "piece", "pieces", "unit",
        "units", "each", "item", "items", "cup", "cups", "tbsp", "tsp", "can", "cans", "bar", "bars",
        "egg", "eggs", "packet", "packets", "bottle", "bottles",
    ]

    enum AmountError: Error, LocalizedError {
        case noServingGramsForGrams(String)
        case noServingGramsForServings(String, String)
        case unknownUnit(String, String)

        var errorDescription: String? {
            switch self {
            case .noServingGramsForGrams(let n): "\(n) is stored per serving with no serving weight, so it can't be logged in grams."
            case .noServingGramsForServings(let n, let u): "\(n) is stored per 100 g with no serving weight, so '\(u)' can't be converted."
            case .unknownUnit(let u, let n): "Unknown unit '\(u)' for \(n)."
            }
        }
    }

    /// Port of `resolve_amount`: (factor on the stored basis, grams eaten).
    static func resolveAmount(_ food: Food, qty: Double, unit rawUnit: String) throws -> (factor: Double, grams: Double?) {
        let unit = rawUnit.lowercased()
        if gramUnits.contains(unit) {
            if food.basis == .per100g { return (qty / 100, qty) }
            guard let sg = food.servingGrams, sg > 0 else { throw AmountError.noServingGramsForGrams(food.name) }
            return (qty / sg, qty)
        }
        let label = norm(food.servingLabel ?? "")
        var plurals: Set<String> = [label, label + "s", label + "es"]
        if label.hasSuffix("y") { plurals.insert(String(label.dropLast()) + "ies") }
        let matchesLabel = !label.isEmpty && plurals.contains(unit)
        if servingUnits.contains(unit) || matchesLabel || unit.isEmpty {
            if food.basis == .serving { return (qty, food.servingGrams.map { qty * $0 }) }
            guard let sg = food.servingGrams, sg > 0 else { throw AmountError.noServingGramsForServings(food.name, unit) }
            return (qty * sg / 100, qty * sg)
        }
        throw AmountError.unknownUnit(unit, food.name)
    }

    /// Macros for an amount of a food, after the fiber adjustment, without logging.
    func preview(_ food: Food, qty: Double, unit: String) -> Macros? {
        guard let (factor, _) = try? Self.resolveAmount(food, qty: qty, unit: unit) else { return nil }
        let kcal = food.kcal * factor
        let fiber = food.fiber.map { $0 * factor }
        let adj = Self.fiberAdjustment(fiber: fiber, soluble: food.fiberSoluble.map { $0 * factor },
                                       insoluble: food.fiberInsoluble.map { $0 * factor }, mode: fiberMode,
                                       kcal: kcal, protein: food.protein * factor, carbs: food.carbs * factor,
                                       fat: food.fat * factor)
        return Macros(kcal: max(0, kcal - adj), protein: food.protein * factor, carbs: food.carbs * factor,
                      fat: food.fat * factor, fiber: fiber ?? 0)
    }

    func preview(_ meal: UsualMeal) -> Macros {
        meal.components.reduce(.zero) { sum, c in
            guard let f = foods[c.foodID], let m = preview(f, qty: c.qty, unit: c.unit) else { return sum }
            return sum + m
        }
    }

    // MARK: helpers

    static func norm(_ s: String) -> String {
        s.lowercased().split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    static func round2(_ x: Double) -> Double { (x * 100).rounded() / 100 }
}

// MARK: - decoding events into models

extension Ledger {
    static let foodFieldNames: Set<String> = [
        "name", "aliases", "basis", "serving_grams", "serving_label", "kcal", "protein", "carbs", "fat",
        "fiber", "fiber_soluble", "fiber_insoluble", "micros", "source", "notes",
    ]

    static func parseMicros(_ v: JSONValue?) -> [String: Double] {
        switch v {
        case .string(let s):
            guard let data = s.data(using: .utf8),
                  let obj = try? JSONDecoder().decode([String: JSONValue].self, from: data) else { return [:] }
            return obj.compactMapValues(\.double)
        case .object(let o): return o.compactMapValues(\.double)
        default: return [:]
        }
    }

    static func microsJSON(_ m: [String: Double]) -> JSONValue {
        guard !m.isEmpty else { return .null }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = (try? encoder.encode(m.mapValues { (($0 * 10000).rounded()) / 10000 })) ?? Data()
        return .string(String(data: data, encoding: .utf8) ?? "{}")
    }

    static func food(from f: [String: JSONValue], id: String, createdAt: String?) -> Food {
        Food(id: id, name: f["name"]?.string ?? "Unnamed",
             aliases: (f["aliases"]?.string ?? "").split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty },
             basis: Basis(rawValue: f["basis"]?.string ?? "serving") ?? .serving,
             servingGrams: f["serving_grams"]?.double, servingLabel: f["serving_label"]?.string,
             kcal: f["kcal"]?.double ?? 0, protein: f["protein"]?.double ?? 0, carbs: f["carbs"]?.double ?? 0,
             fat: f["fat"]?.double ?? 0, fiber: f["fiber"]?.double, fiberSoluble: f["fiber_soluble"]?.double,
             fiberInsoluble: f["fiber_insoluble"]?.double, micros: parseMicros(f["micros"]),
             source: f["source"]?.string, notes: f["notes"]?.string, createdAt: createdAt)
    }

    static func foodFields(_ food: Food) -> [String: JSONValue] {
        [
            "name": .string(food.name), "aliases": .string(food.aliases.joined(separator: ",")),
            "basis": .string(food.basis.rawValue), "serving_grams": JSONValue(food.servingGrams),
            "serving_label": JSONValue(food.servingLabel), "kcal": .number(food.kcal),
            "protein": .number(food.protein), "carbs": .number(food.carbs), "fat": .number(food.fat),
            "fiber": JSONValue(food.fiber), "fiber_soluble": JSONValue(food.fiberSoluble),
            "fiber_insoluble": JSONValue(food.fiberInsoluble), "micros": microsJSON(food.micros),
            "source": JSONValue(food.source), "notes": JSONValue(food.notes),
        ]
    }

    static func entry(from ev: Event, seq: Int, mode: String) -> Entry {
        let kcal = ev.double("kcal") ?? 0
        let adjust = fiberAdjustment(fiber: ev.double("fiber"), soluble: ev.double("fiber_soluble"),
                                     insoluble: ev.double("fiber_insoluble"), mode: mode, kcal: ev.double("kcal"),
                                     protein: ev.double("protein"), carbs: ev.double("carbs"), fat: ev.double("fat"))
        return Entry(id: ev.id, seq: seq, foodID: ev.string("food_id"), label: ev.string("label") ?? "Entry",
                     qty: ev.double("qty") ?? 1, unit: ev.string("unit") ?? "serving", grams: ev.double("grams"),
                     kcal: max(0, round2(kcal - adjust)), kcalLabel: kcal, kcalAdjust: adjust,
                     protein: ev.double("protein") ?? 0, carbs: ev.double("carbs") ?? 0, fat: ev.double("fat") ?? 0,
                     fiber: ev.double("fiber"), fiberSoluble: ev.double("fiber_soluble"),
                     fiberInsoluble: ev.double("fiber_insoluble"), micros: parseMicros(ev["micros"]),
                     eatenOn: ev.string("eaten_on") ?? String(ev.ts.prefix(10)), eatenAt: ev.string("eaten_at"),
                     meal: ev.string("meal").flatMap(MealSlot.init(rawValue:)), source: ev.string("source"),
                     confidence: ev.string("confidence"), note: ev.string("note"), groupID: ev.string("group_id"),
                     groupLabel: ev.string("group_label"), ts: ev.ts)
    }

    static func components(_ v: JSONValue?) -> [UsualMeal.Component] {
        (v?.array ?? []).compactMap { c in
            guard let o = c.object, let fid = o["food_id"]?.string else { return nil }
            return UsualMeal.Component(foodID: fid, qty: o["qty"]?.double ?? 1, unit: o["unit"]?.string ?? "serving")
        }
    }

    static func componentsJSON(_ cs: [UsualMeal.Component]) -> JSONValue {
        .array(cs.map { .object(["food_id": .string($0.foodID), "qty": .number($0.qty), "unit": .string($0.unit)]) })
    }

    static func meal(from ev: Event) -> UsualMeal? {
        guard let id = ev.string("meal_id") ?? (ev.id.isEmpty ? nil : ev.id), let name = ev.string("name") else { return nil }
        return UsualMeal(id: id, name: name,
                         aliases: (ev["aliases"]?.array ?? []).compactMap(\.string),
                         slot: ev.string("slot").flatMap(MealSlot.init(rawValue:)),
                         components: components(ev["components"]), note: ev.string("note"))
    }

    static func plan(from ev: Event) -> PlannedItem? {
        guard let day = ev.string("day"), let label = ev.string("label") else { return nil }
        return PlannedItem(id: ev.id, day: day, label: label, detail: ev.string("detail"),
                           meal: ev.string("meal").flatMap(MealSlot.init(rawValue:)),
                           macros: Macros(kcal: ev.double("kcal") ?? 0, protein: ev.double("protein") ?? 0,
                                          carbs: ev.double("carbs") ?? 0, fat: ev.double("fat") ?? 0,
                                          fiber: ev.double("fiber") ?? 0),
                           mealID: ev.string("meal_ref"), components: components(ev["components"]))
    }
}
