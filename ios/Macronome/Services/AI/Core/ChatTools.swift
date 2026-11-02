import Foundation

/// The chat agent's tools. They run on the phone over the ledger: the model picks foods
/// and amounts, these do every sum, and the cards they leave are what the chat shows.
/// Spec: docs/v2-chat-design.md.
@MainActor
final class ChatTools {
    struct ToolError: LocalizedError {
        var message: String
        init(_ message: String) { self.message = message }
        var errorDescription: String? { message }
    }

    let store: FoodStore
    let today: String
    let now: Date
    private(set) var cards: [ChatCard] = []
    /// Every number a tool returned this turn, as the reply may quote them.
    private(set) var numbers: Set<String> = []

    init(store: FoodStore, today: String = Clock.dayString(), now: Date = Date()) {
        self.store = store
        self.today = today
        self.now = now
    }

    var ledger: Ledger { store.ledger }

    func run(_ call: ToolCall) -> ToolResult {
        let a = call.arguments
        do {
            let out: JSONValue
            switch call.name {
            case "budget": out = budget(day: try day(a["day"]))
            case "preview": out = try preview(a)
            case "show_options": out = try showOptions(a)
            case "solve": out = try solve(a)
            case "log": out = try log(a)
            case "edit_entries": out = try editEntries(a)
            case "delete_entries": out = try deleteEntries(a)
            case "find": out = find(a["query"]?.string ?? "")
            case "history": out = try history(a)
            case "search_entries": out = searchEntries(a)
            case "frequent": out = frequent(a)
            case "set_targets": out = try setTargets(a)
            case "remember": out = try remember(a)
            case "forget": out = try forget(a)
            default: throw ToolError("There is no tool named \(call.name).")
            }
            collectNumbers(out)
            return ToolResult(callID: call.id, name: call.name, content: out.jsonText)
        } catch {
            return ToolResult(callID: call.id, name: call.name, content: "Error: \(error.localizedDescription)", isError: true)
        }
    }

    // MARK: - budget

    /// The meal held back in every budget: the profile's `hold_back_meal`, else the usual
    /// meal named like "Evening bowl". Nothing is held back once it's eaten that day.
    func holdBack(on day: String) -> (meal: UsualMeal, macros: Macros)? {
        let l = ledger
        guard day >= today else { return nil }
        let meal = l.profile["hold_back_meal"].flatMap { l.meals[$0] }
            ?? l.sortedMeals.first { Ledger.norm($0.name).contains("evening") }
        guard let meal else { return nil }
        let names = Set(([meal.name] + meal.aliases).map(Ledger.norm))
        if l.groups(on: day).contains(where: { names.contains(Ledger.norm($0.label)) }) { return nil }
        return (meal, l.preview(meal))
    }

    func status(on day: String, extra: Macros = .zero) -> StatusLine {
        let rows = ledger.macroStatus(on: day, extra: extra)
        func left(_ k: MacroStatus.Key) -> Double? { rows.first { $0.key == k }?.left }
        var s = StatusLine(kcal: left(.kcal), protein: left(.protein), carbs: left(.carbs), fat: left(.fat))
        s.carbsLabel = ledger.carbMode == "net" ? "net C" : "C"
        if let hb = holdBack(on: day) {
            s.holdBack = hb.meal.name
            s.afterHoldBackKcal = s.kcal.map { $0 - hb.macros.kcal }
            s.afterHoldBackProtein = s.protein.map { $0 - hb.macros.protein }
        }
        return s
    }

    func budget(day: String, extra: Macros = .zero) -> JSONValue {
        let rows = ledger.macroStatus(on: day, extra: extra)
        var out: [String: JSONValue] = ["day": .string(day)]
        for r in rows where r.key != .fiber {
            out[r.key.rawValue] = .object([
                "eaten": num(r.eaten), "target": num(r.target), "left": num(r.left),
            ])
        }
        if ledger.carbMode == "net" { out["carbs_are"] = "net of fiber" }
        if let hb = holdBack(on: day) {
            let s = status(on: day, extra: extra)
            out["held_back"] = .object(["meal": .string(hb.meal.name), "kcal": num(hb.macros.kcal), "protein": num(hb.macros.protein)])
            out["left_after_held_back"] = .object(["kcal": num(s.afterHoldBackKcal), "protein": num(s.afterHoldBackProtein)])
        }
        return .object(out)
    }

    // MARK: - items

    struct Part {
        var food: Food?
        var label: String
        var qty: Double
        var unit: String
        var macros: Macros
        var estimate: Bool
    }

    struct Item {
        var label: String
        var mealName: String?
        var parts: [Part]
        var day: String?
        var slot: MealSlot?
        var macros: Macros { parts.reduce(.zero) { $0 + $1.macros } }
    }

    func resolveItem(_ v: JSONValue) throws -> Item {
        guard let o = v.object else { throw ToolError("Each item must be an object.") }
        let estimate = o["estimate"].flatMap { if case .bool(let b) = $0 { return b } else { return nil } } ?? false
        let day = try o["day"].flatMap { $0.isNull ? nil : try self.day($0) }
        let slot = o["slot"]?.string.flatMap { MealSlot(rawValue: $0.lowercased()) }
        let l = ledger
        if let ref = o["meal_id"]?.string ?? o["meal"]?.string {
            guard let meal = l.meals[ref] ?? l.findMeal(ref) else {
                throw ToolError("No usual meal '\(ref)'. Call find to look it up.")
            }
            var comps = meal.components.map { ($0.foodID, $0.qty, $0.unit) }
            for ch in o["changes"]?.array ?? [] {
                guard let c = ch.object, let f = try? food(c["food_id"]?.string ?? c["food"]?.string) else {
                    throw ToolError("A change in \(meal.name) names a food that isn't in the library.")
                }
                let qty = c["qty"]?.double ?? 0
                let unit = c["unit"]?.string ?? comps.first { $0.0 == f.id }?.2 ?? defaultUnit(f)
                if let i = comps.firstIndex(where: { $0.0 == f.id }) {
                    if qty <= 0 { comps.remove(at: i) } else { comps[i] = (f.id, qty, unit) }
                } else if qty > 0 {
                    comps.append((f.id, qty, unit))
                }
            }
            let estimatedFoods = Set((o["estimated_food_ids"]?.array ?? []).compactMap(\.string))
            let parts = try comps.map { comp -> Part in
                let (id, qty, unit) = comp
                guard let f = l.foods[id] else { throw ToolError("\(meal.name) has a part that is no longer in the library.") }
                return try part(f, qty: qty, unit: unit, estimate: estimate || estimatedFoods.contains(id))
            }
            return Item(label: o["label"]?.string ?? meal.name, mealName: meal.name, parts: parts, day: day,
                        slot: slot ?? meal.slot)
        }
        if let ref = o["food_id"]?.string ?? o["food"]?.string {
            let f = try food(ref)
            let unit = o["unit"]?.string ?? defaultUnit(f)
            let qty = o["qty"]?.double ?? 1
            guard qty > 0 else { throw ToolError("The amount for \(f.name) must be more than zero.") }
            return Item(label: o["label"]?.string ?? f.name, parts: [try part(f, qty: qty, unit: unit, estimate: estimate)],
                        day: day, slot: slot)
        }
        if let label = o["label"]?.string, let kcal = o["kcal"]?.double {
            let m = Macros(kcal: kcal, protein: o["protein"]?.double ?? 0, carbs: o["carbs"]?.double ?? 0,
                           fat: o["fat"]?.double ?? 0, fiber: o["fiber"]?.double ?? 0)
            return Item(label: label, parts: [Part(food: nil, label: label, qty: 1, unit: "serving", macros: m, estimate: true)],
                        day: day, slot: slot)
        }
        throw ToolError("An item needs a meal_id, a food_id, or a label with kcal for a one-off estimate.")
    }

    private func food(_ ref: String?) throws -> Food {
        guard let ref, !ref.isEmpty else { throw ToolError("Missing food_id.") }
        if let f = ledger.foods[ref] { return f }
        switch ledger.findFood(ref) {
        case .found(let f): return f
        case .ambiguous(let fs): throw ToolError("'\(ref)' matches several foods: \(fs.prefix(5).map { "\($0.name) [\($0.id)]" }.joined(separator: ", ")).")
        case .none: throw ToolError("No food '\(ref)' in the library. Call find, or log a one-off estimate.")
        }
    }

    private func defaultUnit(_ f: Food) -> String { f.basis == .per100g ? "g" : (f.servingLabel ?? "serving") }

    private func part(_ f: Food, qty: Double, unit: String, estimate: Bool) throws -> Part {
        do {
            _ = try Ledger.resolveAmount(f, qty: qty, unit: unit)
        } catch {
            throw ToolError(error.localizedDescription)
        }
        let m = ledger.preview(f, qty: qty, unit: unit) ?? .zero
        return Part(food: f, label: f.name, qty: qty, unit: unit, macros: m, estimate: estimate)
    }

    private func items(_ a: [String: JSONValue]) throws -> [Item] {
        let list = a["items"]?.array ?? []
        guard !list.isEmpty else { throw ToolError("Pass at least one item.") }
        return try list.map(resolveItem)
    }

    private func macrosJSON(_ m: Macros) -> JSONValue {
        .object(["kcal": num(m.kcal), "protein": num(m.protein), "carbs": num(ledger.carbMode == "net" ? m.netCarbs : m.carbs),
                 "fat": num(m.fat)])
    }

    // MARK: - preview, options, solve

    func preview(_ a: [String: JSONValue]) throws -> JSONValue {
        let day = try day(a["day"])
        let list = try items(a)
        let total = list.reduce(Macros.zero) { $0 + $1.macros }
        let after = status(on: day, extra: total)
        var out: [String: JSONValue] = [
            "items": .array(list.map { .object(["label": .string($0.label), "macros": macrosJSON($0.macros)]) }),
            "total": macrosJSON(total),
            "left_after": .object(["kcal": num(after.kcal), "protein": num(after.protein), "carbs": num(after.carbs), "fat": num(after.fat)]),
        ]
        if let hb = after.holdBack {
            out["left_after_held_back"] = .object(["meal": .string(hb), "kcal": num(after.afterHoldBackKcal),
                                                    "protein": num(after.afterHoldBackProtein)])
        }
        return .object(out)
    }

    func showOptions(_ a: [String: JSONValue]) throws -> JSONValue {
        let day = try day(a["day"])
        let options = a["options"]?.array ?? []
        guard !options.isEmpty else { throw ToolError("Pass at least one option.") }
        let s = status(on: day)
        let budget = s.afterHoldBackKcal ?? s.kcal
        let proteinNeed = s.afterHoldBackProtein ?? s.protein
        var rows: [OptionsCard.Row] = []
        var json: [JSONValue] = []
        for opt in options {
            guard let o = opt.object else { continue }
            let list = try (o["items"]?.array ?? []).map(resolveItem)
            guard !list.isEmpty else { throw ToolError("Option '\(o["label"]?.string ?? "")' has no items.") }
            let m = list.reduce(Macros.zero) { $0 + $1.macros }
            let label = o["label"]?.string ?? list.map(\.label).joined(separator: " + ")
            let spare = budget.map { $0 - m.kcal }
            let hits = proteinNeed.map { m.protein >= $0 - 0.5 } ?? false
            rows.append(OptionsCard.Row(label: label, kcal: m.kcal.rounded(), protein: m.protein.rounded(),
                                        spare: spare?.rounded(), hitsProtein: hits))
            var r: [String: JSONValue] = ["label": .string(label), "kcal": num(m.kcal), "protein": num(m.protein)]
            if let spare { r[spare >= 0 ? "spare" : "over"] = num(abs(spare)) }
            if let need = proteinNeed {
                let gap = m.protein - need
                r[gap >= 0 ? "protein_over_need" : "protein_short"] = num(abs(gap))
            }
            json.append(.object(r))
        }
        let hb = holdBack(on: day)
        cards.append(.options(OptionsCard(title: a["title"]?.string ?? "Option", rows: rows, budgetKcal: budget?.rounded(),
                                          budgetProtein: proteinNeed?.rounded(), holdBack: hb?.meal.name,
                                          holdBackKcal: hb?.macros.kcal.rounded(), holdBackProtein: hb?.macros.protein.rounded())))
        var out: [String: JSONValue] = ["shown_as_card": true, "options": .array(json), "budget_kcal": num(budget),
                                        "protein_needed": num(proteinNeed)]
        if let hb { out["held_back"] = .string(hb.meal.name) }
        return .object(out)
    }

    /// Amounts of a usual meal's variable parts that fit a budget. One part: the most of
    /// it that fits. Two parts: a few pairs trading one for the other.
    func solve(_ a: [String: JSONValue]) throws -> JSONValue {
        let day = try day(a["day"])
        guard let ref = a["meal_id"]?.string, let meal = ledger.meals[ref] ?? ledger.findMeal(ref) else {
            throw ToolError("solve needs a usual meal's meal_id.")
        }
        let vary = try (a["vary"]?.array ?? []).compactMap(\.string).map { try food($0) }
        guard (1...2).contains(vary.count) else { throw ToolError("vary takes one or two food ids from the meal.") }
        let s = status(on: day)
        guard let budget = a["kcal_budget"]?.double ?? s.afterHoldBackKcal ?? s.kcal else {
            throw ToolError("No calorie target is set, so there is no budget to solve for.")
        }
        let varyIDs = Set(vary.map(\.id))
        var fixed = Macros.zero
        for c in meal.components where !varyIDs.contains(c.foodID) {
            if let f = ledger.foods[c.foodID], let m = ledger.preview(f, qty: c.qty, unit: c.unit) { fixed += m }
        }
        for f in vary where f.basis == .serving && f.servingGrams == nil {
            throw ToolError("\(f.name) has no gram weight, so it can't be solved for.")
        }
        func kcal(_ f: Food, _ g: Double) -> Double { ledger.preview(f, qty: g, unit: "g")?.kcal ?? 0 }
        func protein(_ f: Food, _ g: Double) -> Double { ledger.preview(f, qty: g, unit: "g")?.protein ?? 0 }
        func maxGrams(_ f: Food, room: Double, step: Double) -> Double {
            var g = 0.0
            while kcal(f, g + step) <= room && g < 3000 { g += step }
            return g
        }
        let room = budget - fixed.kcal
        guard room > 0 else { throw ToolError("The meal's fixed parts alone use the budget.") }
        var combos: [JSONValue] = []
        if vary.count == 1 {
            let g = maxGrams(vary[0], room: room, step: 5)
            let total = fixed.kcal + kcal(vary[0], g)
            combos.append(.object([vary[0].name: num(g), "kcal": num(total), "protein": num(fixed.protein + protein(vary[0], g))]))
        } else {
            let (a0, b0) = (vary[0], vary[1])
            let defaultB = meal.components.first { $0.foodID == b0.id }.map { c in
                (try? Ledger.resolveAmount(b0, qty: c.qty, unit: c.unit))?.grams ?? 100
            } ?? 100
            let start = max(50, (defaultB / 10).rounded() * 10)
            for b in [start, start + 50, start + 100] {
                let roomA = room - kcal(b0, b)
                guard roomA > 0 else { break }
                let g = maxGrams(a0, room: roomA, step: 5)
                guard g >= 50 else { break }
                let total = fixed.kcal + kcal(a0, g) + kcal(b0, b)
                let p = fixed.protein + protein(a0, g) + protein(b0, b)
                combos.append(.object([a0.name: num(g), b0.name: num(b), "kcal": num(total), "protein": num(p)]))
            }
        }
        return .object(["meal": .string(meal.name), "budget_kcal": num(budget), "amounts_in_grams": .array(combos)])
    }

    // MARK: - writes

    func log(_ a: [String: JSONValue]) throws -> JSONValue {
        let callDay = try day(a["day"])
        let callSlot = a["slot"]?.string.flatMap { MealSlot(rawValue: $0.lowercased()) }
        let list = try items(a)
        let replace = (a["replace_entry_ids"]?.array ?? []).compactMap(\.string).filter { id in ledger.entries.contains { $0.id == id } }
        let groupLabel = a["label"]?.string

        var events: [Event] = replace.map(Commands.deleteEntry)
        var groups: [LogCard.DayGroup] = []
        var entryIDs: [String] = []
        // Loose foods in one call are one dish ("salad"); usual meals are their own rows.
        var looseGroup: [String: String] = [:]
        for item in list {
            let day = item.day ?? callDay
            let slot = item.slot ?? callSlot ?? (day == today ? MealSlot.guess(at: now) : nil)
            let name: String
            let gid: String
            if item.mealName != nil || groupLabel == nil {
                name = item.label
                gid = EventID.make()
            } else {
                name = groupLabel!
                let key = day + (slot?.rawValue ?? "")
                gid = looseGroup[key] ?? EventID.make()
                looseGroup[key] = gid
            }
            var rows: [LogCard.Row] = []
            for p in item.parts {
                let ev: Event
                if let f = p.food {
                    ev = try Commands.log(f, qty: p.qty, unit: p.unit, day: day, meal: slot, source: "chat",
                                          confidence: p.estimate ? "estimate" : "high", note: p.estimate ? "estimate" : nil,
                                          groupID: gid, groupLabel: name, at: now)
                } else {
                    ev = Commands.logEstimate(label: p.label, macros: p.macros, day: day, meal: slot, source: "chat",
                                              confidence: "estimate", note: "estimate", groupID: gid, groupLabel: name)
                }
                events.append(ev)
                entryIDs.append(ev.id)
                rows.append(LogCard.Row(label: Format.shortName(p.label), amount: p.food == nil ? nil : Format.amount(qty: p.qty, unit: p.unit),
                                           kcal: p.macros.kcal.rounded(), estimate: p.estimate))
            }
            if let i = groups.firstIndex(where: { $0.day == day && $0.name == name && $0.slot == slot?.title }) {
                groups[i].rows += rows
            } else {
                groups.append(LogCard.DayGroup(day: day, title: dayTitle(day), slot: slot?.title, name: name, rows: rows))
            }
        }
        store.append(events)

        let s = status(on: today)
        cards.append(.logged(LogCard(groups: groups, entryIDs: entryIDs, assumption: a["assumption"]?.string,
                                        status: s, replacedEventIDs: replace)))
        var out: [String: JSONValue] = [
            "logged": .array(groups.map { g in
                .object(["day": .string(g.day), "slot": JSONValue(g.slot), "name": .string(g.name), "kcal": num(g.kcal)])
            }),
            "entry_ids": .array(entryIDs.map { .string($0) }),
            "today_left": budget(day: today),
            "shown_as_card": true,
        ]
        if !replace.isEmpty { out["replaced"] = num(Double(replace.count)) }
        return .object(out)
    }

    /// New amounts for entries already logged: a part weighed later ("300 grams" for the
    /// cauliflower) or a correction ("it was 13 g"). Same food, day, slot and meal.
    func editEntries(_ a: [String: JSONValue]) throws -> JSONValue {
        let edits = a["edits"]?.array?.compactMap(\.object) ?? []
        guard !edits.isEmpty else { throw ToolError("Pass edits: entry_id and the new qty.") }
        var events: [Event] = []
        var replaced: [String] = []
        var entryIDs: [String] = []
        var groups: [LogCard.DayGroup] = []
        for edit in edits {
            guard let id = edit["entry_id"]?.string, let e = ledger.entries.first(where: { $0.id == id }) else {
                throw ToolError("No entry with id \(edit["entry_id"]?.string ?? "?"). Today's entry ids are in the context.")
            }
            guard let qty = edit["qty"]?.double, qty > 0 else { throw ToolError("The new amount must be more than zero.") }
            let unit = edit["unit"]?.string ?? e.unit
            let estimate = edit["estimate"].flatMap { if case .bool(let b) = $0 { return b } else { return nil } } ?? false
            let ev: Event
            let kcal: Double
            if let fid = e.foodID, let f = ledger.foods[fid] {
                let p = try part(f, qty: qty, unit: unit, estimate: estimate)
                ev = try Commands.log(f, qty: qty, unit: unit, day: e.eatenOn, meal: e.meal, source: "chat",
                                      confidence: estimate ? "estimate" : "high", note: estimate ? "estimate" : nil,
                                      groupID: e.groupID, groupLabel: e.groupLabel, at: Clock.parseISO(e.eatenAt) ?? now)
                kcal = p.macros.kcal
            } else {
                // A one-off estimate scales with its amount.
                let k = qty / max(e.qty, 0.0001)
                let m = Macros(kcal: e.kcal * k, protein: e.protein * k, carbs: e.carbs * k, fat: e.fat * k, fiber: (e.fiber ?? 0) * k)
                ev = Commands.logEstimate(label: e.label, macros: m, day: e.eatenOn, meal: e.meal, source: "chat",
                                          groupID: e.groupID, groupLabel: e.groupLabel)
                kcal = m.kcal
            }
            events += [Commands.deleteEntry(id), ev]
            replaced.append(id)
            entryIDs.append(ev.id)
            let row = LogCard.Row(label: Format.shortName(e.label), amount: Format.amount(qty: qty, unit: unit),
                                  kcal: kcal.rounded(), estimate: estimate)
            let name = e.groupLabel ?? Format.shortName(e.label)
            if let i = groups.firstIndex(where: { $0.day == e.eatenOn && $0.name == name }) {
                groups[i].rows.append(row)
            } else {
                groups.append(LogCard.DayGroup(day: e.eatenOn, title: dayTitle(e.eatenOn), slot: e.meal?.title, name: name, rows: [row]))
            }
        }
        store.append(events)
        cards.append(.logged(LogCard(groups: groups, entryIDs: entryIDs, assumption: a["assumption"]?.string,
                                     status: status(on: today), replacedEventIDs: replaced, edited: true)))
        return .object(["edited": num(Double(replaced.count)), "entry_ids": .array(entryIDs.map { .string($0) }),
                        "today_left": budget(day: today), "shown_as_card": true])
    }

    func deleteEntries(_ a: [String: JSONValue]) throws -> JSONValue {
        let ids = (a["entry_ids"]?.array ?? []).compactMap(\.string)
        let known = ids.filter { id in ledger.entries.contains { $0.id == id } }
        guard !known.isEmpty else { throw ToolError("None of those entry ids are in the log.") }
        store.append(known.map(Commands.deleteEntry))
        return .object(["deleted": num(Double(known.count)), "today_left": budget(day: today)])
    }

    func setTargets(_ a: [String: JSONValue]) throws -> JSONValue {
        let keys: [(MacroStatus.Key, String, String)] = [(.kcal, "Calories", ""), (.protein, "Protein", " g"),
                                                          (.carbs, ledger.carbMode == "net" ? "Net carbs" : "Carbs", " g"),
                                                          (.fat, "Fat", " g")]
        let was = ledger.standingTargets
        var events: [Event] = []
        var rows: [TargetsCard.Row] = []
        var previous: [String: String] = [:]
        for (key, label, unit) in keys {
            guard let v = a[key.rawValue]?.double else {
                rows.append(TargetsCard.Row(label: label, was: was[key], now: was[key], unit: unit))
                continue
            }
            guard v > 0, v < 10000 else { throw ToolError("\(label) target \(v) isn't plausible.") }
            events.append(Commands.setTarget(key, v))
            previous["target_\(key.rawValue)"] = ledger.profile["target_\(key.rawValue)"] ?? ""
            rows.append(TargetsCard.Row(label: label, was: was[key], now: v, unit: unit))
        }
        guard !events.isEmpty else { throw ToolError("Pass at least one of kcal, protein, carbs, fat.") }
        store.append(events)
        cards.append(.targets(TargetsCard(rows: rows, eventIDs: events.map(\.id), previous: previous)))
        let now = ledger.standingTargets
        var out: [String: JSONValue] = ["shown_as_card": true]
        for (key, _, _) in keys { out[key.rawValue] = .object(["was": num(was[key]), "now": num(now[key])]) }
        if let p = now.protein, let c = now.carbs, let f = now.fat {
            out["kcal_from_macros"] = num(p * 4 + c * 4 + f * 9)
        }
        let cut: [String: JSONValue] = [
            "protein": num(((was.protein ?? 0) - (now.protein ?? 0)) * 4),
            "carbs": num(((was.carbs ?? 0) - (now.carbs ?? 0)) * 4),
            "fat": num(((was.fat ?? 0) - (now.fat ?? 0)) * 9),
        ]
        out["kcal_change_by_macro"] = .object(cut)
        return .object(out)
    }

    func remember(_ a: [String: JSONValue]) throws -> JSONValue {
        guard let text = a["text"]?.string?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
            throw ToolError("remember needs the text to keep.")
        }
        let kind = a["kind"]?.string.flatMap { ["rule", "meal", "like", "fact"].contains($0) ? $0 : nil } ?? "like"
        let ev = a["key"]?.string.map { Commands.remember(text, kind: kind, key: $0) } ?? Commands.remember(text, kind: kind)
        store.append(ev)
        let key = ev.string("key") ?? ""
        cards.append(.remembered(RememberedCard(key: key, kind: kind, text: text)))
        return .object(["remembered": .string(text), "key": .string(key), "shown_as_card": true])
    }

    func forget(_ a: [String: JSONValue]) throws -> JSONValue {
        guard let key = a["key"]?.string, ledger.memoryNotes.contains(where: { $0.key == key }) else {
            throw ToolError("No memory with that key.")
        }
        store.append(Commands.forgetMemory(key))
        return .object(["forgot": .string(key)])
    }

    // MARK: - reading the log

    func find(_ query: String) -> JSONValue {
        let q = Ledger.norm(query)
        let foods = ledger.searchFoods(query).prefix(12).map { f -> JSONValue in
            .object(["food_id": .string(f.id), "name": .string(f.name), "units": .string(ChatPrompt.unitHint(f))])
        }
        let meals = ledger.sortedMeals.filter { m in
            q.isEmpty || Ledger.norm(m.name).contains(q) || m.aliases.contains { Ledger.norm($0).contains(q) }
                || m.components.contains { c in ledger.foods[c.foodID].map { Ledger.norm($0.name).contains(q) } ?? false }
        }.map { m -> JSONValue in
            .object(["meal_id": .string(m.id), "name": .string(m.name),
                     "parts": .array(m.components.compactMap { c in
                         ledger.foods[c.foodID].map { .string("\(Format.trim(c.qty, digits: 2)) \(c.unit) \($0.name) [\($0.id)]") }
                     })])
        }
        return .object(["foods": .array(Array(foods)), "meals": .array(meals)])
    }

    func history(_ a: [String: JSONValue]) throws -> JSONValue {
        let end = try day(a["end"] ?? .string(today))
        let start = try day(a["start"] ?? .string(Clock.addDays(end, -6)))
        guard start <= end else { throw ToolError("start is after end.") }
        var days: [JSONValue] = []
        var d = start
        var sum = Macros.zero
        var count = 0
        while d <= end && days.count < 92 {
            let t = ledger.totals(on: d)
            if t.count > 0 {
                let targets = ledger.targets(on: d)
                days.append(.object(["day": .string(d), "macros": macrosJSON(t.macros), "target_kcal": num(targets.kcal),
                                     "target_protein": num(targets.protein)]))
                sum += t.macros
                count += 1
            }
            d = Clock.addDays(d, 1)
        }
        var out: [String: JSONValue] = ["start": .string(start), "end": .string(end), "days": .array(days)]
        if count > 0 {
            let n = Double(count)
            out["average_per_logged_day"] = macrosJSON(Macros(kcal: sum.kcal / n, protein: sum.protein / n, carbs: sum.carbs / n,
                                                              fat: sum.fat / n, fiber: sum.fiber / n))
        }
        return .object(out)
    }

    func searchEntries(_ a: [String: JSONValue]) -> JSONValue {
        let q = Ledger.norm(a["query"]?.string ?? "")
        let days = Int(a["days"]?.double ?? 30)
        let since = Clock.addDays(today, -max(1, days))
        let hits = ledger.entries.filter { e in
            e.eatenOn >= since && (q.isEmpty || Ledger.norm(e.label).contains(q) || Ledger.norm(e.groupLabel ?? "").contains(q))
        }
        .sorted { ($0.eatenOn, $0.seq) > ($1.eatenOn, $1.seq) }
        .prefix(40)
        .map { e -> JSONValue in
            .object(["entry_id": .string(e.id), "day": .string(e.eatenOn), "slot": JSONValue(e.meal?.rawValue),
                     "food": .string(e.label), "amount": .string(e.amountText), "kcal": num(e.kcal),
                     "meal": JSONValue(e.groupLabel)])
        }
        return .object(["entries": .array(Array(hits))])
    }

    func frequent(_ a: [String: JSONValue]) -> JSONValue {
        let days = Int(a["days"]?.double ?? 30)
        let slot = a["slot"]?.string.flatMap { MealSlot(rawValue: $0.lowercased()) }
        let since = Clock.addDays(today, -max(1, days))
        let logged = ledger.loggedDays.filter { $0 >= since }
        var mealDays: [String: Set<String>] = [:]
        var mealKcal: [String: [Double]] = [:]
        var foodDays: [String: Set<String>] = [:]
        var foodQty: [String: [Double]] = [:]
        var foodUnit: [String: String] = [:]
        for d in logged {
            for g in ledger.groups(on: d) where slot == nil || g.meal == slot {
                mealDays[g.label, default: []].insert(d)
                mealKcal[g.label, default: []].append(g.macros.kcal)
                for e in g.entries {
                    foodDays[e.label, default: []].insert(d)
                    foodQty[e.label, default: []].append(e.qty)
                    foodUnit[e.label] = e.unit
                }
            }
        }
        func avg(_ xs: [Double]) -> Double { xs.isEmpty ? 0 : xs.reduce(0, +) / Double(xs.count) }
        let meals = mealDays.sorted { ($0.value.count, $1.key) > ($1.value.count, $0.key) }.prefix(12).map { k, v -> JSONValue in
            .object(["name": .string(k), "days": num(Double(v.count)), "average_kcal": num(avg(mealKcal[k] ?? []))])
        }
        let foods = foodDays.sorted { ($0.value.count, $1.key) > ($1.value.count, $0.key) }.prefix(15).map { k, v -> JSONValue in
            .object(["food": .string(k), "days": num(Double(v.count)),
                     "typical_amount": .string("\(Format.trim(avg(foodQty[k] ?? []), digits: 2)) \(foodUnit[k] ?? "")")])
        }
        return .object(["days_logged": num(Double(logged.count)), "meals": .array(Array(meals)), "foods": .array(Array(foods))])
    }

    // MARK: - helpers

    /// "today", "yesterday", "tomorrow" or YYYY-MM-DD; nil means today.
    func day(_ v: JSONValue?) throws -> String {
        guard let s = v?.string?.trimmingCharacters(in: .whitespaces).lowercased(), !s.isEmpty else { return today }
        switch s {
        case "today": return today
        case "yesterday", "last night": return Clock.addDays(today, -1)
        case "tomorrow": return Clock.addDays(today, 1)
        default:
            guard Clock.date(fromDay: s) != nil else { throw ToolError("Days are YYYY-MM-DD, today, yesterday or tomorrow; got '\(s)'.") }
            return s
        }
    }

    func dayTitle(_ day: String) -> String {
        if day == today { return "Today" }
        if day == Clock.addDays(today, -1) { return "Yesterday" }
        if day == Clock.addDays(today, 1) { return "Tomorrow" }
        return Format.dayHeader(day)
    }

    private func num(_ x: Double?, digits: Int = 0) -> JSONValue {
        guard let x, x.isFinite else { return .null }
        let p = pow(10, Double(digits))
        return .number((x * p).rounded() / p)
    }

    private func collectNumbers(_ v: JSONValue) {
        switch v {
        case .number(let n):
            numbers.insert(String(Int(n.rounded())))
            numbers.insert(Format.trim(n))
        case .array(let a): a.forEach(collectNumbers)
        case .object(let o): o.values.forEach(collectNumbers)
        case .string(let s):
            for m in s.matches(of: /\d+(\.\d+)?/) { numbers.insert(String(s[m.range])) }
        default: break
        }
    }

    /// Lets the context's numbers (what's left today) be quoted too.
    func allowNumbers(in text: String) {
        collectNumbers(.string(text.replacingOccurrences(of: ",", with: "")))
    }
}
