import Foundation

/// What the local parser made of one utterance.
struct LogParse: Sendable {
    var text: String
    var items: [ParsedItem]
    /// Set when the words name a meal ("for lunch", "this morning").
    var slot: MealSlot?
    /// Items matched by sound rather than spelling, with the name they were read as.
    var readings: [UUID: String] = [:]

    var unresolved: [ParsedItem] { items.filter { !$0.isResolved } }
}

/// The free, offline interpreter. Splits an utterance into items, reads amounts and
/// units, then matches usual meals first and foods second against the user's own
/// library, tolerating dictation mistakes.
struct LocalLogInterpreter: LogInterpreter {
    func interpret(_ text: String, ledger: Ledger) async throws -> [ParsedItem] {
        parse(text, ledger: ledger).items
    }

    // MARK: vocabulary

    static let separators: Set<String> = [",", ".", ";", "!", "?", "and", "with", "plus", "then", "also", "&", "+"]

    static let slotWords: [String: MealSlot] = [
        "breakfast": .breakfast, "brunch": .breakfast, "lunch": .lunch, "dinner": .dinner, "supper": .dinner,
        "snack": .snack, "dessert": .snack,
    ]

    /// Said before the food and meaning nothing ("I just had", "log", "um").
    static let leadingFiller: Set<String> = [
        "i", "ive", "im", "id", "just", "had", "have", "having", "ate", "eaten", "eat", "eating", "log", "logged",
        "add", "also", "and", "then", "so", "ok", "okay", "um", "uh", "please", "got", "grabbed", "drank", "drink",
        "finished", "made", "well", "yeah", "now", "another", "with", "plus", "of",
    ]
    static let trailingFiller: Set<String> = ["please", "thanks", "too", "again", "today", "tonight", "earlier", "now"]
    static let fillerPhrases: [[String]] = [
        ["before", "bed"], ["before", "i", "went", "to", "bed"], ["just", "now"], ["a", "minute", "ago"],
        ["this", "evening"], ["this", "afternoon"], ["as", "well"], ["for", "today"],
    ]

    /// Canonical unit for each spoken form. Serving labels from the library are added
    /// per ledger ("patties" -> "patty").
    static let units: [String: String] = {
        var u: [String: String] = [
            "g": "g", "gram": "g", "grams": "g", "gm": "g", "gms": "g", "gr": "g", "grammes": "g",
            "ml": "ml", "milliliter": "ml", "milliliters": "ml", "millilitre": "ml", "millilitres": "ml",
            "tbsp": "tbsp", "tablespoon": "tbsp", "tablespoons": "tbsp", "tbsps": "tbsp",
            "tsp": "tsp", "teaspoon": "tsp", "teaspoons": "tsp",
            "serving": "serving", "servings": "serving", "serve": "serving", "serves": "serving",
            "portion": "serving", "portions": "serving",
            "tin": "can", "tins": "can",
        ]
        for w in ["cup", "scoop", "slice", "piece", "can", "bar", "packet", "pack", "bottle", "bag", "block", "egg", "item", "unit"] {
            u[w] = w
            u[w + "s"] = w
        }
        return u
    }()

    func unitTable(_ ledger: Ledger) -> [String: String] {
        var table = Self.units
        for food in ledger.foods.values {
            guard let label = food.servingLabel?.lowercased(), !label.contains(" "), !label.isEmpty else { continue }
            if table[label] == nil { table[label] = label }
            for plural in [label + "s", label + "es", label.hasSuffix("y") ? String(label.dropLast()) + "ies" : label] where table[plural] == nil {
                table[plural] = label
            }
        }
        return table
    }

    // MARK: parse

    func parse(_ text: String, ledger: Ledger) -> LogParse {
        var result = LogParse(text: text, items: [])
        var tokens = NumberWords.tokens(text)
        result.slot = Self.extractSlot(&tokens)
        tokens = Self.removePhrases(tokens)
        tokens = protectNames(tokens, ledger: ledger)

        let units = unitTable(ledger)
        let library = Library(ledger: ledger)
        var currentMeal: UsualMeal?

        for segment in Self.segments(tokens) {
            guard var seg = Segment(segment, units: units) else { continue }
            // "cauliflower, 100 grams": an amount on its own belongs to the item before it.
            if seg.phrase.isEmpty {
                if let last = result.items.indices.last, result.items[last].foodID != nil, result.items[last].qty == nil {
                    result.items[last].qty = seg.qty
                    result.items[last].unit = seg.unit
                    continue
                }
                // "3 eggs" with nothing before it: the unit was the food.
                guard let word = seg.unitWord else { continue }
                seg.phrase = [word]
            }
            let phraseText = seg.phrase.joined(separator: " ").replacingOccurrences(of: "_", with: " ")
            var item = ParsedItem(phrase: segment.joined(separator: " ").replacingOccurrences(of: "_", with: " "),
                                  qty: seg.qty, unit: seg.unit)
            item.label = phraseText

            // Inside a usual meal, a named component is an override of that component.
            if let meal = currentMeal {
                let ids = Set(meal.components.map(\.foodID))
                if let hit = library.food(phraseText, words: seg.phrase, unit: seg.unit, within: ids) {
                    item.foodID = hit.food.id
                    item.alternatives = hit.alternatives
                    if hit.fuzzy { result.readings[item.id] = hit.food.name }
                    result.items.append(item)
                    continue
                }
            }

            let mealHit = library.meal(phraseText, words: seg.phrase)
            let foodHit = library.food(phraseText, words: seg.phrase, unit: seg.unit, within: nil)
            let preferFood = seg.explicitAmount
            let useMeal: Bool
            switch (mealHit, foodHit) {
            case (nil, nil): useMeal = false
            case (.some, nil): useMeal = true
            case (nil, .some): useMeal = false
            case let (.some(m), .some(f)):
                if m.exact != f.exact { useMeal = m.exact }
                else if abs(m.score - f.score) > 0.05 { useMeal = m.score > f.score }
                else { useMeal = !preferFood }
            }

            if useMeal, let m = mealHit {
                item.mealID = m.meal.id
                item.label = m.meal.name
                item.unit = nil
                // "half a potato bowl" scales it; a bare "a" or "the" does not.
                if !seg.explicitAmount { item.qty = nil }
                if m.fuzzy { result.readings[item.id] = m.meal.name }
                currentMeal = m.meal
                seg.phrase = []
            } else if let f = foodHit {
                item.foodID = f.food.id
                item.alternatives = f.alternatives
                if f.fuzzy { result.readings[item.id] = f.food.name }
            }
            result.items.append(item)
        }
        return result
    }

    // MARK: steps

    /// Pulls "for lunch", "at dinner", "as a snack", "this morning" out of the tokens.
    static func extractSlot(_ t: inout [String]) -> MealSlot? {
        var slot: MealSlot?
        var i = 0
        while i < t.count {
            if ["for", "at", "with", "during", "as"].contains(t[i]) {
                var j = i + 1
                if j < t.count, ["my", "the", "a", "an", "our"].contains(t[j]) { j += 1 }
                // "for lunch" ends a clause; "with a snack bowl" names a meal.
                let after = j + 1 < t.count ? t[j + 1] : nil
                let endsClause = after.map { separators.contains($0) || leadingFiller.contains($0) || ["the", "my", "a", "an"].contains($0) } ?? true
                if j < t.count, let s = slotWords[t[j]], endsClause {
                    slot = s
                    t.removeSubrange(i...j)
                    continue
                }
            }
            if t[i] == "this", i + 1 < t.count, t[i + 1] == "morning" {
                slot = slot ?? .breakfast
                t.removeSubrange(i...(i + 1))
                continue
            }
            i += 1
        }
        // "Lunch: potato bowl", "breakfast was the standard bowl"
        if slot == nil, let first = t.first, let s = slotWords[first], t.count > 1, [",", ".", "was", "is"].contains(t[1]) {
            slot = s
            t.removeFirst(2)
        }
        return slot
    }

    static func removePhrases(_ tokens: [String]) -> [String] {
        var t = tokens
        for phrase in fillerPhrases.sorted(by: { $0.count > $1.count }) {
            var i = 0
            while i + phrase.count <= t.count {
                if Array(t[i..<(i + phrase.count)]) == phrase { t.removeSubrange(i..<(i + phrase.count)) } else { i += 1 }
            }
        }
        return t
    }

    /// Names that contain a separator word ("salt and vinegar chips") are glued with
    /// underscores so the split leaves them whole.
    func protectNames(_ tokens: [String], ledger: Ledger) -> [String] {
        let names = ledger.foods.values.flatMap { [$0.name] + $0.aliases } + ledger.meals.values.flatMap { [$0.name] + $0.aliases }
        let risky = names.map(Fuzzy.tokens).filter { $0.count > 1 && $0.contains(where: Self.separators.contains) }
        var t = tokens
        for name in risky.sorted(by: { $0.count > $1.count }) {
            var i = 0
            while i + name.count <= t.count {
                if Array(t[i..<(i + name.count)]) == name {
                    t.replaceSubrange(i..<(i + name.count), with: [name.joined(separator: "_")])
                }
                i += 1
            }
        }
        return t
    }

    /// Splits on separators, and before a number that follows words ("potato bowl 350
    /// potato"), since dictation often drops the commas.
    static func segments(_ tokens: [String]) -> [[String]] {
        var out: [[String]] = []
        var cur: [String] = []
        for tok in tokens {
            if separators.contains(tok) {
                if !cur.isEmpty { out.append(cur) }
                cur = []
                continue
            }
            if NumberWords.value(of: tok) != nil, let prev = cur.last, NumberWords.value(of: prev) == nil,
               !["a", "an", "of", "the"].contains(prev), cur.contains(where: { !leadingFiller.contains($0) }) {
                out.append(cur)
                cur = []
            }
            cur.append(tok)
        }
        if !cur.isEmpty { out.append(cur) }
        return out
    }
}

// MARK: - segment

/// One item's words split into amount, unit and the food words.
private struct Segment {
    var qty: Double?
    var unit: String?
    var phrase: [String]
    /// A number or unit was spoken, not just "a" or "the".
    var explicitAmount = false
    /// The unit as spoken, for "3 meatballs" where it is also the food.
    var unitWord: String?

    init?(_ raw: [String], units: [String: String]) {
        var t = raw
        while let f = t.first, LocalLogInterpreter.leadingFiller.contains(f) { t.removeFirst() }
        while let l = t.last, LocalLogInterpreter.trailingFiller.contains(l) { t.removeLast() }
        guard !t.isEmpty else { return nil }

        if let f = t.first, f == "a" || f == "an" {
            qty = 1
            t.removeFirst()
        } else if let f = t.first, let v = NumberWords.value(of: f) {
            qty = v
            explicitAmount = true
            t.removeFirst()
        }
        // "scoop of protein" after "another": one of the unit.
        if qty == nil, t.count > 2, units[t[0]] != nil, t[1] == "of" { qty = 1 }
        if qty != nil, let f = t.first, let u = units[f] {
            unit = u
            unitWord = f
            explicitAmount = true
            t.removeFirst()
            // "3 meatballs": a serving label from the library is also the food's name.
            if t.isEmpty, LocalLogInterpreter.units[f] == nil { t = [f] }
        }
        // "cauliflower 100 grams", "potato 350"
        if qty == nil, t.count >= 2 {
            if let u = units[t[t.count - 1]], let v = NumberWords.value(of: t[t.count - 2]) {
                qty = v; unit = u; explicitAmount = true
                t.removeLast(2)
            } else if let v = NumberWords.value(of: t[t.count - 1]) {
                qty = v; explicitAmount = true
                t.removeLast()
            }
        }
        while let f = t.first, ["of", "the", "my", "some", "a", "an", "x"].contains(f) { t.removeFirst() }
        while let l = t.last, LocalLogInterpreter.trailingFiller.contains(l) { t.removeLast() }
        phrase = t
    }
}

// MARK: - library matching

private struct Library {
    struct Name {
        var tokens: [String]
        var normalized: String
    }

    struct MealHit { var meal: UsualMeal; var score: Double; var exact: Bool; var fuzzy: Bool }
    struct FoodHit { var food: Food; var score: Double; var exact: Bool; var fuzzy: Bool; var alternatives: [String] }

    let ledger: Ledger
    let mealNames: [(meal: UsualMeal, names: [Name], vocab: Set<String>)]
    let foodNames: [(food: Food, names: [Name], vocab: Set<String>)]
    /// Food id -> the sequence number it was last logged at.
    let lastUsed: [String: Int]

    init(ledger: Ledger) {
        self.ledger = ledger
        func names(_ list: [String]) -> [Name] {
            list.map { Name(tokens: Fuzzy.tokens($0), normalized: Fuzzy.tokens($0).joined(separator: " ")) }.filter { !$0.tokens.isEmpty }
        }
        mealNames = ledger.sortedMeals.map { m in
            let n = names([m.name] + m.aliases)
            return (m, n, Set(n.flatMap { Fuzzy.content($0.tokens) }))
        }
        foodNames = ledger.sortedFoods.map { f in
            let n = names([f.name] + f.aliases)
            return (f, n, Set(n.flatMap { Fuzzy.content($0.tokens) }))
        }
        var used: [String: Int] = [:]
        for e in ledger.entries { if let id = e.foodID { used[id] = max(used[id] ?? 0, e.seq) } }
        lastUsed = used
    }

    func meal(_ phrase: String, words: [String]) -> MealHit? {
        let words = words.flatMap { $0.split(separator: "_").map(String.init) }
        let normalized = words.joined(separator: " ")
        if let m = ledger.findMeal(phrase) ?? ledger.findMeal(normalized) { return MealHit(meal: m, score: 1, exact: true, fuzzy: false) }
        var best: MealHit?
        for entry in mealNames {
            for name in entry.names {
                guard let m = Fuzzy.match(segment: words, name: name.tokens, vocabulary: entry.vocab) else { continue }
                let threshold = Fuzzy.content(name.tokens).count == 1 ? 0.8 : 0.75
                guard m.score >= threshold else { continue }
                if best == nil || m.score > best!.score {
                    best = MealHit(meal: entry.meal, score: m.score, exact: m.isExact, fuzzy: !m.isExact)
                }
            }
        }
        return best
    }

    func food(_ phrase: String, words: [String], unit: String?, within ids: Set<String>?) -> FoodHit? {
        let words = words.flatMap { $0.split(separator: "_").map(String.init) }
        guard !words.isEmpty else { return nil }
        let allowed: (Food) -> Bool = { ids?.contains($0.id) ?? true }

        // 1. The engine's own lookup, accepted only when every spoken word is a whole
        // word of the food's names, so "on" never partially matches "onion".
        var queries = [words.joined(separator: " ")]
        if let last = words.last, Fuzzy.singular(last) != last {
            queries.append((words.dropLast() + [Fuzzy.singular(last)]).joined(separator: " "))
        }
        for q in queries where q.count >= 3 {
            switch ledger.findFood(q) {
            case .found(let f) where allowed(f) && wholeWords(words, of: f):
                return FoodHit(food: f, score: 1, exact: true, fuzzy: false, alternatives: [])
            case .ambiguous(let list):
                let fits = list.filter { allowed($0) && wholeWords(words, of: $0) }
                if let pick = choose(fits, unit: unit) { return pick }
            default:
                break
            }
        }

        // 2. Sound-alike and misspelt names.
        var scored: [(food: Food, score: Double, exact: Bool)] = []
        for entry in foodNames where allowed(entry.food) {
            var top: Fuzzy.Match?
            for name in entry.names {
                guard let m = Fuzzy.match(segment: words, name: name.tokens, vocabulary: entry.vocab) else { continue }
                let threshold = Fuzzy.content(name.tokens).count == 1 ? 0.8 : 0.75
                if m.score >= threshold, top == nil || m.score > top!.score { top = m }
            }
            if let top { scored.append((entry.food, top.score, top.isExact)) }
        }
        guard let best = scored.max(by: { $0.score < $1.score }) else { return nil }
        let close = scored.filter { best.score - $0.score <= 0.03 }.map(\.food)
        if close.count > 1, var pick = choose(close, unit: unit) {
            pick.exact = best.exact
            pick.fuzzy = !best.exact
            pick.score = best.score
            return pick
        }
        return FoodHit(food: best.food, score: best.score, exact: best.exact, fuzzy: !best.exact, alternatives: [])
    }

    /// Every spoken word is a word of the food's names, and the last one is a name's
    /// head noun: "milk" finds almond milk, but "banana" does not find banana peppers.
    private func wholeWords(_ words: [String], of food: Food) -> Bool {
        let names = ([food.name] + food.aliases).map(Fuzzy.tokens)
        let vocab = Set(names.flatMap { $0 })
        let spoken = Fuzzy.content(words)
        guard let last = spoken.last else { return false }
        let heads = Set(names.compactMap { $0.last.map(Fuzzy.singular) })
        return spoken.allSatisfy { w in vocab.contains(w) || vocab.contains(Fuzzy.singular(w)) || vocab.contains(w + "s") }
            && heads.contains(Fuzzy.singular(last))
    }

    /// Several foods fit: keep the ones whose serving label is the spoken unit, then
    /// take the one logged most recently. The rest are offered on the card.
    private func choose(_ foods: [Food], unit: String?) -> FoodHit? {
        guard !foods.isEmpty else { return nil }
        var pool = foods
        if let unit, !Ledger.gramUnits.contains(unit) {
            let labelled = foods.filter { ($0.servingLabel?.lowercased()).map { Fuzzy.singular($0) == Fuzzy.singular(unit) } ?? false }
            if !labelled.isEmpty { pool = labelled }
        }
        let ranked = pool.sorted { (lastUsed[$0.id] ?? -1, $1.name) > (lastUsed[$1.id] ?? -1, $0.name) }
        let pick = ranked[0]
        let others = ranked.dropFirst().prefix(2).map(\.id)
        return FoodHit(food: pick, score: 1, exact: pool.count == 1, fuzzy: false, alternatives: Array(others))
    }
}
