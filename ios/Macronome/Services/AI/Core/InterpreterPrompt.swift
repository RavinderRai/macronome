import Foundation

/// One item as a model returned it, before it is checked against the library.
struct InterpretedItem: Hashable, Sendable {
    var phrase: String?
    var foodID: String?
    var mealID: String?
    var qty: Double?
    var unit: String?
    var label: String?
    var kcal: Double?
    var protein: Double?
    var carbs: Double?
    var fat: Double?
    var fiber: Double?
}

/// Prompt and validation for the fast-tier log interpreter: a phrase the local parser
/// could not resolve becomes items against Ravi's own foods and meals.
enum InterpreterPrompt {
    static let rules = """
    You turn what Ravi says he ate into log items for his food tracker. Match each thing to his food \
    library or usual meals below. Return one item per food or meal.
    - Known food: food_id from the list, qty and unit as he said them. Units: "g", "ml", "serving", or the \
    food's unit shown in the list. No amount given means qty 1 of the food's unit.
    - A usual meal he names ("the potato bowl", "usual breakfast"): meal_id from the list, no components.
    - Restaurant food or anything not in the library: no food_id; give a short label and your best \
    estimate of kcal, protein, carbs and fat for the amount eaten.
    - Never invent ids. Copy them exactly from the lists.
    Reply with JSON only: {"items": [{"phrase": "150 g chicken", "food_id": "a1b2c3", "qty": 150, "unit": "g"}, \
    {"phrase": "the potato bowl", "meal_id": "potato_bowl"}, {"phrase": "a chipotle bowl", "label": "Chipotle bowl", \
    "kcal": 850, "protein": 45, "carbs": 90, "fat": 32}]}
    """

    /// The compact library: ids, names, aliases and units, no macros (the model does not need them).
    static func library(_ ledger: Ledger, limit: Int = 150) -> String {
        var out = "Foods (id | name | aka | units):\n"
        out += ledger.sortedFoods.prefix(limit).map { f in
            var s = "- \(f.id) | \(f.name)"
            if !f.aliases.isEmpty { s += " | aka \(f.aliases.prefix(4).joined(separator: ", "))" }
            return s + " | " + ChatPrompt.unitHint(f)
        }.joined(separator: "\n")
        let meals = ledger.sortedMeals
        if !meals.isEmpty {
            out += "\n\nUsual meals (meal_id | name | aka):\n"
            out += meals.map { m in
                "- \(m.id) | \(m.name)" + (m.aliases.isEmpty ? "" : " | aka \(m.aliases.joined(separator: ", "))")
            }.joined(separator: "\n")
        }
        return out
    }

    static func request(_ text: String, ledger: Ledger) -> ModelRequest {
        ModelRequest(system: [rules, library(ledger)], messages: [ModelMessage(role: .user, text: text)],
                     jsonMode: true, maxTokens: 800, timeout: 30)
    }

    static func parse(_ raw: String) -> [InterpretedItem] {
        guard let obj = ChatReplyParser.jsonObject(in: raw) else { return [] }
        let list = obj["items"]?.array ?? []
        return list.compactMap { v in
            guard let o = v.object else { return nil }
            return InterpretedItem(phrase: o["phrase"]?.string, foodID: o["food_id"]?.string, mealID: o["meal_id"]?.string,
                                   qty: o["qty"]?.double, unit: o["unit"]?.string, label: o["label"]?.string ?? o["name"]?.string,
                                   kcal: o["kcal"]?.double, protein: o["protein"]?.double, carbs: o["carbs"]?.double,
                                   fat: o["fat"]?.double, fiber: o["fiber"]?.double)
        }
    }

    /// Checks every id against the ledger. Unknown ids fall back to an estimate when
    /// the model gave numbers, else to an unresolved item so the user can pick.
    static func validate(_ items: [InterpretedItem], text: String, ledger: Ledger) -> [ParsedItem] {
        items.compactMap { it in
            let phrase = (it.phrase?.isEmpty == false ? it.phrase : nil) ?? it.label ?? text
            var p = ParsedItem(phrase: phrase)
            if let mid = it.mealID, !mid.isEmpty, let meal = ledger.meals[mid] ?? ledger.findMeal(mid) {
                p.mealID = meal.id
                p.label = meal.name
                return p
            }
            if let fid = it.foodID, let food = ledger.foods[fid] {
                p.foodID = food.id
                p.label = food.name
                let qty = (it.qty ?? 0) > 0 ? it.qty! : 1
                p.qty = qty
                p.unit = validUnit(it.unit, food: food, qty: qty)
                return p
            }
            if let kcal = it.kcal, kcal > 0 {
                p.estimate = Macros(kcal: kcal, protein: it.protein ?? 0, carbs: it.carbs ?? 0, fat: it.fat ?? 0,
                                    fiber: it.fiber ?? 0)
                p.label = it.label ?? phrase
                p.qty = 1
                p.unit = "serving"
                return p
            }
            // Nothing usable: surface the closest library names so the user can choose.
            let query = it.label ?? phrase
            switch ledger.findFood(query) {
            case .found(let f): p.alternatives = [f.name]
            case .ambiguous(let fs): p.alternatives = fs.prefix(4).map(\.name)
            case .none: break
            }
            p.label = it.label
            return p
        }
    }

    /// The model's unit when the food can be logged in it, else the food's own unit.
    static func validUnit(_ unit: String?, food: Food, qty: Double) -> String {
        let u = (unit ?? "").trimmingCharacters(in: .whitespaces).lowercased()
        if !u.isEmpty, (try? Ledger.resolveAmount(food, qty: qty, unit: u)) != nil { return u }
        return food.basis == .per100g && food.servingGrams == nil ? "g" : "serving"
    }
}
