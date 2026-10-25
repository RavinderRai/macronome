import Foundation

/// Reads the OCR text of a nutrition facts panel into a FoodDraft. Pure and
/// deterministic, so the same text always gives the same draft.
///
/// Follows food-log/CLAUDE.md: numbers as printed, basis from the label, serving grams
/// whenever printed, every other nutrient into micros under the fixed keys, and %DV-only
/// nutrients converted with the Canadian/US daily values. Handles bilingual Canadian
/// panels ("Fat / Lipides 2 g 3 %"), US panels, decimal commas, "<1 g", and the usual
/// OCR confusions (O for 0, l for 1, "g" read as "9", missing spaces).
///
/// `uncertain` holds draft property names for the core fields (kcal, protein, carbs,
/// fat, fiber, fiberSoluble, fiberInsoluble, servingGrams, servingLabel) and micros
/// keys for the rest.
enum NutritionLabelParser {
    enum Unit: String, Sendable { case kcal, g, mg, ug }

    struct Nutrient: Sendable {
        var key: String
        var unit: Unit
        var words: [String]
        /// Daily value in `unit`, for labels that print only a percentage.
        var dv: Double?
    }

    static let coreKeys: Set<String> = ["kcal", "protein", "carbs", "fat", "fiber", "fiberSoluble", "fiberInsoluble"]
    private static let ignore = "_ignore"

    /// Keywords are matched folded (lowercase, no accents) on word boundaries, longest
    /// first, so "saturated fat" wins over "fat" and "insoluble" over "soluble".
    static let nutrients: [Nutrient] = [
        Nutrient(key: "kcal", unit: .kcal, words: ["calories", "calorie", "energy", "energie", "valeur energetique"]),
        Nutrient(key: "fat", unit: .g, words: ["total fat", "fat", "lipides", "lipids", "matieres grasses", "total lipides"], dv: 75),
        Nutrient(key: "sat_fat_g", unit: .g, words: ["saturated fat", "saturated", "saturates", "sat fat", "satures", "gras satures", "acides gras satures"], dv: 20),
        Nutrient(key: "trans_fat_g", unit: .g, words: ["trans fat", "trans", "gras trans", "acides gras trans"]),
        Nutrient(key: "polyunsaturated_fat_g", unit: .g, words: ["polyunsaturated fat", "polyunsaturated", "polyunsaturates", "polyinsatures"]),
        Nutrient(key: "monounsaturated_fat_g", unit: .g, words: ["monounsaturated fat", "monounsaturated", "monounsaturates", "monoinsatures"]),
        Nutrient(key: "omega3_g", unit: .g, words: ["omega-3", "omega 3", "omega3"]),
        Nutrient(key: "cholesterol_mg", unit: .mg, words: ["cholesterol"], dv: 300),
        Nutrient(key: "sodium_mg", unit: .mg, words: ["sodium"], dv: 2300),
        Nutrient(key: "carbs", unit: .g, words: ["total carbohydrate", "total carbohydrates", "carbohydrate", "carbohydrates", "glucides", "total carbs", "carbs"], dv: 275),
        Nutrient(key: "fiber", unit: .g, words: ["dietary fiber", "dietary fibre", "fibre", "fiber", "fibres", "fibers", "fibres alimentaires", "total fibre"], dv: 28),
        Nutrient(key: "fiberSoluble", unit: .g, words: ["soluble fibre", "soluble fiber", "fibres solubles", "fibre soluble", "soluble"]),
        Nutrient(key: "fiberInsoluble", unit: .g, words: ["insoluble fibre", "insoluble fiber", "fibres insolubles", "fibre insoluble", "insoluble"]),
        Nutrient(key: "sugar_g", unit: .g, words: ["total sugars", "sugars", "sugar", "sucres"], dv: 100),
        Nutrient(key: "added_sugar_g", unit: .g, words: ["added sugars", "added sugar", "sucres ajoutes"], dv: 50),
        Nutrient(key: "protein", unit: .g, words: ["protein", "proteins", "proteines", "proteine"]),
        Nutrient(key: "potassium_mg", unit: .mg, words: ["potassium"], dv: 4700),
        Nutrient(key: "calcium_mg", unit: .mg, words: ["calcium"], dv: 1300),
        Nutrient(key: "iron_mg", unit: .mg, words: ["iron", "fer"], dv: 18),
        Nutrient(key: "magnesium_mg", unit: .mg, words: ["magnesium"], dv: 420),
        Nutrient(key: "zinc_mg", unit: .mg, words: ["zinc"], dv: 11),
        Nutrient(key: "phosphorus_mg", unit: .mg, words: ["phosphorus", "phosphore"], dv: 1250),
        Nutrient(key: "vitamin_a_ug", unit: .ug, words: ["vitamin a", "vitamine a"], dv: 900),
        Nutrient(key: "vitamin_c_mg", unit: .mg, words: ["vitamin c", "vitamine c"], dv: 90),
        Nutrient(key: "vitamin_d_ug", unit: .ug, words: ["vitamin d", "vitamine d"], dv: 20),
        Nutrient(key: "vitamin_e_mg", unit: .mg, words: ["vitamin e", "vitamine e"], dv: 15),
        Nutrient(key: "vitamin_k_ug", unit: .ug, words: ["vitamin k", "vitamine k"], dv: 120),
        Nutrient(key: "thiamin_mg", unit: .mg, words: ["thiamin", "thiamine", "vitamin b1", "vitamine b1"], dv: 1.2),
        Nutrient(key: "riboflavin_mg", unit: .mg, words: ["riboflavin", "riboflavine", "vitamin b2", "vitamine b2"], dv: 1.3),
        Nutrient(key: "niacin_mg", unit: .mg, words: ["niacin", "niacine", "vitamin b3", "vitamine b3"], dv: 16),
        Nutrient(key: "vitamin_b6_mg", unit: .mg, words: ["vitamin b6", "vitamine b6"], dv: 1.7),
        Nutrient(key: "folate_ug", unit: .ug, words: ["folate", "folic acid", "acide folique", "folacine"], dv: 400),
        Nutrient(key: "vitamin_b12_ug", unit: .ug, words: ["vitamin b12", "vitamine b12"], dv: 2.4),
        Nutrient(key: "caffeine_mg", unit: .mg, words: ["caffeine"]),
        // Not in the food-log list; same name_unit pattern.
        Nutrient(key: "biotin_ug", unit: .ug, words: ["biotin", "biotine"], dv: 30),
        Nutrient(key: "pantothenate_mg", unit: .mg, words: ["pantothenate", "pantothenic acid", "acide pantothenique"], dv: 5),
        Nutrient(key: "selenium_ug", unit: .ug, words: ["selenium"], dv: 55),
        Nutrient(key: "copper_mg", unit: .mg, words: ["copper", "cuivre"], dv: 0.9),
        Nutrient(key: "manganese_mg", unit: .mg, words: ["manganese"], dv: 2.3),
        Nutrient(key: "iodine_ug", unit: .ug, words: ["iodine", "iode"], dv: 150),
        Nutrient(key: "choline_mg", unit: .mg, words: ["choline"], dv: 550),
        // Words that own a stretch of a line so its numbers are not given to a neighbour.
        Nutrient(key: ignore, unit: .g, words: [
            "calories from fat", "calories provenant des lipides", "% daily value", "% valeur quotidienne", "%dv", "daily value", "valeur quotidienne", "% dv",
            "servings per container", "portions par contenant", "starch", "amidon", "sugar alcohols", "polyols",
        ]),
    ]

    static let nutrientByKey: [String: Nutrient] = Dictionary(nutrients.map { ($0.key, $0) }, uniquingKeysWith: { a, _ in a })

    /// Pretty name for a micros key, for the form.
    static func displayName(_ key: String) -> String {
        let names: [String: String] = [
            "sat_fat_g": "Saturated fat", "trans_fat_g": "Trans fat", "sugar_g": "Sugars", "added_sugar_g": "Added sugars",
            "cholesterol_mg": "Cholesterol", "sodium_mg": "Sodium", "potassium_mg": "Potassium", "calcium_mg": "Calcium",
            "iron_mg": "Iron", "magnesium_mg": "Magnesium", "zinc_mg": "Zinc", "phosphorus_mg": "Phosphorus",
            "vitamin_a_ug": "Vitamin A", "vitamin_c_mg": "Vitamin C", "vitamin_d_ug": "Vitamin D", "vitamin_e_mg": "Vitamin E",
            "vitamin_k_ug": "Vitamin K", "thiamin_mg": "Thiamin", "riboflavin_mg": "Riboflavin", "niacin_mg": "Niacin",
            "vitamin_b6_mg": "Vitamin B6", "folate_ug": "Folate", "vitamin_b12_ug": "Vitamin B12", "omega3_g": "Omega-3",
            "caffeine_mg": "Caffeine", "polyunsaturated_fat_g": "Polyunsaturated fat", "monounsaturated_fat_g": "Monounsaturated fat",
            "biotin_ug": "Biotin", "pantothenate_mg": "Pantothenate", "selenium_ug": "Selenium", "copper_mg": "Copper",
            "manganese_mg": "Manganese", "iodine_ug": "Iodine", "choline_mg": "Choline",
        ]
        if let n = names[key] { return n }
        let parts = key.split(separator: "_").dropLast()
        let s = parts.joined(separator: " ")
        return s.prefix(1).uppercased() + s.dropFirst()
    }

    /// "mg" for "sodium_mg".
    static func unitSuffix(_ key: String) -> String {
        guard let last = key.split(separator: "_").last else { return "" }
        return last == "ug" ? "µg" : String(last)
    }

    /// The micros keys food-log uses, in label order, for "Add a nutrient".
    static let microKeys: [String] = nutrients.map(\.key).filter { !coreKeys.contains($0) && $0 != ignore }

    // MARK: - entry points

    static func parse(_ text: String) -> FoodDraft {
        var pass = Pass()
        let lines = text.components(separatedBy: .newlines).map(clean).filter { !$0.isEmpty }
        pass.readServing(lines)
        for (i, line) in lines.enumerated() {
            pass.readNutrients(line, next: i + 1 < lines.count ? lines[i + 1] : nil)
        }
        return pass.finish(raw: text)
    }

    /// Share of the core fields found (serving, kcal, protein, carbs, fat), for the live
    /// "reading" bar and to decide when the read is good enough to capture.
    static func coverage(_ d: FoodDraft) -> Double {
        let serving = d.basis == .per100g || d.servingGrams != nil
        let found = [serving, d.kcal != nil, d.protein != nil, d.carbs != nil, d.fat != nil].filter { $0 }.count
        return Double(found) / 5
    }

    /// Missing calories or a macro: worth offering the vision model.
    static func looksPoor(_ d: FoodDraft) -> Bool {
        d.kcal == nil || d.protein == nil || d.carbs == nil || d.fat == nil
    }

    // MARK: - text cleanup

    /// Fold accents and case, fix the common OCR digit confusions, and normalize
    /// decimal commas. Everything downstream works on this form.
    static func clean(_ raw: String) -> String {
        var s = raw
        for (a, b) in [("\u{00A0}", " "), ("’", "'"), ("‘", "'"), ("‚", ","), ("，", ","), ("–", "-"), ("—", "-"), ("\t", " ")] {
            s = s.replacingOccurrences(of: a, with: b)
        }
        s = s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US_POSIX")).lowercased()
        let rules: [(String, String)] = [
            // "per l bar" -> "per 1 bar"
            (#"\b(per|pour|par|size)\s+[li|]\s"#, "$1 1 "),
            // O and o for zero next to digits, or alone before a unit: "2O0", "Og", "O mg".
            (#"(?<=[\d.])o(?!z)"#, "0"),
            (#"(?<![a-z])o(?=[.,]?\d)"#, "0"),
            (#"(?<![a-z])o(?=\s?(?:g|mg|mcg|ug|%)(?![a-z]))"#, "0"),
            // l, I and | for one: "2l0", "lg", "l2 g".
            (#"(?<=\d)[li|](?=[\d\s%]|g|mg|$)"#, "1"),
            (#"(?<![a-z])[l|](?=\d)"#, "1"),
            (#"(?<![a-z])[l|](?=\s?(?:g|mg)(?![a-z]))"#, "1"),
            // "2,5 mg" -> "2.5 mg"; "2,000" -> "2000".
            (#"(\d),(\d{3})(?!\d)"#, "$1$2"),
            (#"(\d)\s?,\s?(\d{1,2})(?!\d)"#, "$1.$2"),
            (#"\s+"#, " "),
        ]
        for (pattern, template) in rules {
            s = regex(pattern).stringByReplacingMatches(in: s, range: NSRange(s.startIndex..., in: s), withTemplate: template)
        }
        return s.trimmingCharacters(in: .whitespaces)
    }

    /// Footnotes and the ingredient list, which name nutrients without giving amounts.
    static func isNoise(_ line: String) -> Bool {
        let phrases = ["a day", "per day", "par jour", "nutrition advice", "or less is", "ou moins c'est", "is used for",
                       "contributes", "ingredient", "contains:", "contient", "may contain", "peut contenir"]
        if phrases.contains(where: line.contains) { return true }
        return line.filter { $0 == "," }.count >= 4
    }

    // MARK: - regex helpers

    nonisolated(unsafe) private static var cache: [String: NSRegularExpression] = [:]
    private static let cacheLock = NSLock()

    static func regex(_ pattern: String) -> NSRegularExpression {
        cacheLock.lock()
        defer { cacheLock.unlock() }
        if let r = cache[pattern] { return r }
        let r = try! NSRegularExpression(pattern: pattern)
        cache[pattern] = r
        return r
    }

    /// Every keyword with its nutrient, longest first.
    private static let keywords: [(word: String, key: String)] = nutrients
        .flatMap { n in n.words.map { ($0, n.key) } }
        .sorted { $0.0.count > $1.0.count }

    private static func keywordPattern(_ word: String) -> String {
        let escaped = NSRegularExpression.escapedPattern(for: word).replacingOccurrences(of: " ", with: #"\s*"#)
        return #"(?<![a-z])"# + escaped + #"(?![a-z])"#
    }

    struct Hit { var key: String; var range: NSRange }

    static func hits(in line: String) -> [Hit] {
        let ns = line as NSString
        var taken = IndexSet()
        var out: [Hit] = []
        for (word, key) in keywords where line.contains(word.split(separator: " ").first.map(String.init) ?? word) {
            for m in regex(keywordPattern(word)).matches(in: line, range: NSRange(location: 0, length: ns.length)) {
                let r = m.range
                if taken.intersects(integersIn: r.location..<(r.location + r.length)) { continue }
                taken.insert(integersIn: r.location..<(r.location + r.length))
                out.append(Hit(key: key, range: r))
            }
        }
        return out.sorted { $0.range.location < $1.range.location }
    }

    struct Number {
        var value: Double
        var raw: String
        var unit: String?
        var lessThan: Bool
    }

    static func numbers(in s: String) -> [Number] {
        let pattern = #"(<|less than|moins de|moins d')?\s*(\d+(?:\.\d+)?)\s*(kcal|kj|mcg|mg|µg|μg|ug|grams|gram|gr|g|iu|ui|ml|cal|%)?(?![a-z])"#
        let ns = s as NSString
        return regex(pattern).matches(in: s, range: NSRange(location: 0, length: ns.length)).compactMap { m in
            let raw = ns.substring(with: m.range(at: 2))
            guard let v = Double(raw) else { return nil }
            let unit = m.range(at: 3).location == NSNotFound ? nil : ns.substring(with: m.range(at: 3))
            return Number(value: v, raw: raw, unit: unit, lessThan: m.range(at: 1).location != NSNotFound)
        }
    }

    // MARK: - serving

    struct Serving: Equatable {
        var basis: Basis = .serving
        var grams: Double?
        var label: String? = "serving"
        var note: String?
    }

    /// "1 cup (40 g) / pour 1 tasse (40 g)" -> cup, 40 g. A serving that is not one unit
    /// ("1/2 cup (130 mL)") is stored as "serving" with a note, the way food-log does it,
    /// so "1 cup" never means half a cup.
    static func parseServing(_ tail: String) -> Serving? {
        let ns = tail as NSString
        let split = regex(#"\s+/|/\s+|/\s*(?:pour|par)\b|\s(?:pour|par)\s"#).firstMatch(in: tail, range: NSRange(location: 0, length: ns.length))
        let english = split.map { ns.substring(to: $0.range.location) } ?? tail

        func grams(in s: String) -> (Double, String)? {
            let r = regex(#"(\d+(?:\.\d+)?)\s*(g|ml|grams?)(?![a-z])"#)
            let n = s as NSString
            guard let m = r.firstMatch(in: s, range: NSRange(location: 0, length: n.length)),
                  let v = Double(n.substring(with: m.range(at: 1))) else { return nil }
            return (v, n.substring(with: m.range(at: 2)) == "ml" ? "mL" : "g")
        }

        let qtyRegex = regex(#"^\s*(\d+\s+\d\s*/\s*\d|\d+\s*/\s*\d+|\d+(?:\.\d+)?|½|¼|¾|⅓|⅔)?\s*([^()\d/]*)"#)
        let en = english as NSString
        var qty: Double?
        var qtyText = ""
        var words = ""
        if let m = qtyRegex.firstMatch(in: english, range: NSRange(location: 0, length: en.length)) {
            if m.range(at: 1).location != NSNotFound {
                qtyText = en.substring(with: m.range(at: 1))
                qty = fraction(qtyText)
            }
            if m.range(at: 2).location != NSNotFound {
                words = en.substring(with: m.range(at: 2)).trimmingCharacters(in: CharacterSet.letters.inverted)
            }
        }

        var out = Serving()
        let firstWord = words.split(separator: " ").first.map(String.init) ?? ""
        if ["g", "ml", "gram", "grams", "gr"].contains(firstWord), let q = qty {
            // "Per 100 g", "Per 30 g".
            if q == 100 {
                out.basis = .per100g
                out.label = nil
            } else {
                out.grams = q
            }
            return out
        }
        let weight = grams(in: english) ?? grams(in: tail)
        out.grams = weight?.0
        guard qty != nil || out.grams != nil || !words.isEmpty else { return nil }
        let unit = servingUnit(words)
        let q = qty ?? 1
        if abs(q - 1) < 0.001 {
            out.label = unit ?? "serving"
        } else {
            out.label = "serving"
            let what = [qtyText, words].filter { !$0.isEmpty }.joined(separator: " ")
            out.note = "serving is " + what + (weight.map { " (\(Format.trim($0.0)) \($0.1))" } ?? "")
        }
        return out
    }

    static func fraction(_ s: String) -> Double? {
        let t = s.replacingOccurrences(of: " ", with: "")
        switch t {
        case "½": return 0.5
        case "¼": return 0.25
        case "¾": return 0.75
        case "⅓": return 1.0 / 3
        case "⅔": return 2.0 / 3
        default: break
        }
        let parts = s.split(whereSeparator: { $0 == " " }).map(String.init).filter { !$0.isEmpty }
        // "1 1/2" or "1 1 / 2"
        let joined = parts.joined(separator: " ")
        if let m = regex(#"^(\d+)\s+(\d)\s*/\s*(\d)$"#).firstMatch(in: joined, range: NSRange(location: 0, length: (joined as NSString).length)) {
            let n = joined as NSString
            let w = Double(n.substring(with: m.range(at: 1))) ?? 0
            let a = Double(n.substring(with: m.range(at: 2))) ?? 0
            let b = Double(n.substring(with: m.range(at: 3))) ?? 1
            return b == 0 ? nil : w + a / b
        }
        if t.contains("/") {
            let ab = t.split(separator: "/").compactMap { Double($0) }
            guard ab.count == 2, ab[1] != 0 else { return nil }
            return ab[0] / ab[1]
        }
        return Double(t)
    }

    /// The word you would log it by: "tasse" -> "cup", "slices" -> "slice".
    static func servingUnit(_ words: String) -> String? {
        let w = words.trimmingCharacters(in: .whitespaces)
        guard !w.isEmpty else { return nil }
        let table: [(prefixes: [String], unit: String)] = [
            (["cup", "tasse"], "cup"),
            (["tbsp", "tablespoon", "c. a soupe", "c. a table", "c.a.s", "cuillere a soupe", "cuilleres a soupe", "c a soupe", "ml cuillere"], "tbsp"),
            (["tsp", "teaspoon", "c. a the", "c.a.t", "cuillere a the", "cuilleres a the", "c a the"], "tsp"),
            (["scoop", "mesure", "mesurette", "cuillere-mesure", "cuillere mesure"], "scoop"),
            (["slice", "tranche"], "slice"),
            (["piece", "morceau"], "piece"),
            (["bar", "barre"], "bar"),
            (["can", "conserve", "boite"], "can"),
            (["bottle", "bouteille"], "bottle"),
            (["egg", "oeuf"], "egg"),
            (["packet", "sachet", "pouch", "envelope"], "packet"),
            (["sausage", "saucisse"], "sausage"),
            (["cookie", "biscuit"], "cookie"),
            (["cracker", "craquelin"], "cracker"),
            (["patty", "patties", "galette"], "patty"),
            (["tortilla"], "tortilla"),
            (["container", "contenant", "pot "], "container"),
            (["serving", "portion"], "serving"),
        ]
        for row in table where row.prefixes.contains(where: { w.hasPrefix($0) }) { return row.unit }
        guard var first = w.split(separator: " ").first.map(String.init), first.count >= 2,
              first.allSatisfy(\.isLetter) else { return nil }
        if first.hasSuffix("ies") { first = String(first.dropLast(3)) + "y" } else if first.hasSuffix("s") && !first.hasSuffix("ss") {
            first = String(first.dropLast())
        }
        return first
    }

    // MARK: - one pass over the lines

    private struct Pass {
        var values: [String: Double] = [:]
        var raw: [String: String] = [:]
        var bare: Set<String> = []
        var uncertain: Set<String> = []
        var converted: [String] = []
        var serving: Serving?

        mutating func readServing(_ lines: [String]) {
            let lead = regex(#"(?<![a-z])(?:serving size|taille de la portion|serving|portion|per|pour|par)(?![a-z])\s*:?\s*(.*)$"#)
            for (i, line) in lines.enumerated() {
                if isNoise(line) || ["container", "contenant", "amount per", "teneur", "package", "emballage"].contains(where: line.contains) { continue }
                let ns = line as NSString
                guard let m = lead.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)) else { continue }
                var tail = ns.substring(with: m.range(at: 1))
                if tail.trimmingCharacters(in: .whitespaces).isEmpty, i + 1 < lines.count { tail = lines[i + 1] }
                // A nutrient line that happens to contain "per" is not the serving.
                if !hits(in: tail).filter({ $0.key != ignore }).isEmpty && numbers(in: tail).isEmpty { continue }
                if let s = parseServing(tail) {
                    serving = s
                    return
                }
            }
        }

        mutating func readNutrients(_ line: String, next: String?) {
            if isNoise(line) { return }
            let found = hits(in: line)
            guard !found.isEmpty else { return }
            let ns = line as NSString
            var line = line
            // "Saturated + Trans / saturés + trans 2 g": one figure for both, kept as
            // saturated and flagged.
            var combined = false
            if regex(#"satur\w*\s*(fat\s*)?\+\s*trans"#).firstMatch(in: line, range: NSRange(location: 0, length: ns.length)) != nil {
                combined = true
                line = line.replacingOccurrences(of: "trans", with: "     ")
            }
            let all = combined ? hits(in: line) : found

            // Consecutive hits of the same nutrient are one stretch: "Iron / Fer 3 mg".
            var groups: [[Hit]] = []
            for h in all {
                if let last = groups.last?.last, last.key == h.key { groups[groups.count - 1].append(h) } else { groups.append([h]) }
            }
            let text = line as NSString
            for (gi, group) in groups.enumerated() {
                let key = group[0].key
                if key == ignore { continue }
                let start = group[0].range.location + group[0].range.length
                let end = gi + 1 < groups.count ? groups[gi + 1][0].range.location : text.length
                guard end >= start else { continue }
                let mutable = NSMutableString(string: text.substring(with: NSRange(location: start, length: end - start)))
                for h in group.dropFirst() {
                    let r = NSRange(location: h.range.location - start, length: h.range.length)
                    mutable.replaceCharacters(in: r, with: String(repeating: " ", count: r.length))
                }
                var nums = numbers(in: mutable as String)
                // "Includes 10g Added Sugars 20%": the amount comes first.
                if gi == 0, !nums.contains(where: { $0.unit != "%" }) {
                    nums = numbers(in: text.substring(to: group[0].range.location)).filter { $0.unit != "%" } + nums
                }
                // "Calories" on one line and "230" on the next.
                if nums.isEmpty, gi == groups.count - 1, let next, hits(in: next).isEmpty,
                   next.first?.isNumber == true || next.hasPrefix("<") {
                    nums = numbers(in: next)
                }
                record(key, nums)
                if combined && key == "sat_fat_g" { uncertain.insert(key) }
            }
        }

        mutating func record(_ key: String, _ nums: [Number]) {
            guard values[key] == nil, let n = nutrientByKey[key] else { return }
            let amount: Number? = key == "kcal"
                ? (nums.first { $0.unit == "kcal" || $0.unit == "cal" } ?? nums.first { $0.unit != "%" })
                : nums.first { $0.unit != "%" }
            if let a = amount {
                var (v, unsure) = convert(a, to: n)
                if a.lessThan {
                    v /= 2
                    unsure = true
                }
                values[key] = round(v)
                raw[key] = a.raw
                if a.unit == nil && key != "kcal" { bare.insert(key) }
                if unsure { uncertain.insert(key) }
            } else if let pct = nums.first(where: { $0.unit == "%" }), let dv = n.dv {
                values[key] = round(pct.value / 100 * dv)
                uncertain.insert(key)
                converted.append(key)
            }
        }

        /// Into the key's fixed unit. A unit that makes the amount absurd is taken as a
        /// misread ("125 g" sodium).
        func convert(_ n: Number, to nutrient: Nutrient) -> (Double, Bool) {
            let v = n.value
            guard let unit = n.unit else { return (v, nutrient.key != "kcal") }
            let scale: [String: Double] = ["g": 1, "gr": 1, "gram": 1, "grams": 1, "mg": 0.001, "mcg": 1e-6, "ug": 1e-6, "µg": 1e-6, "μg": 1e-6]
            switch nutrient.unit {
            case .kcal:
                if unit == "kj" { return (v / 4.184, true) }
                return (v, false)
            case .g, .mg, .ug:
                if unit == "iu" || unit == "ui" {
                    switch nutrient.key {
                    case "vitamin_d_ug": return (v * 0.025, true)
                    case "vitamin_a_ug": return (v * 0.3, true)
                    case "vitamin_e_mg": return (v * 0.67, true)
                    default: return (v, true)
                    }
                }
                guard let from = scale[unit] else { return (v, true) }
                let to: Double = nutrient.unit == .g ? 1 : nutrient.unit == .mg ? 0.001 : 1e-6
                let out = v * from / to
                if let dv = nutrient.dv, out > dv * 50, from != to { return (v, true) }
                return (out, false)
            }
        }

        func round(_ x: Double) -> Double { (x * 1000).rounded() / 1000 }

        mutating func finish(raw text: String) -> FoodDraft {
            var d = FoodDraft()
            d.source = "label_photo"
            d.rawText = text
            let s = serving ?? Serving()
            if serving == nil { uncertain.insert("servingGrams") }
            d.basis = s.basis
            d.servingGrams = s.grams
            d.servingLabel = s.basis == .per100g ? nil : s.label
            if s.basis == .serving, s.grams == nil, serving != nil { uncertain.insert("servingGrams") }

            repairNineForG(servingGrams: s.grams)

            d.kcal = values["kcal"]
            d.protein = values["protein"]
            d.carbs = values["carbs"]
            d.fat = values["fat"]
            d.fiber = values["fiber"]
            d.fiberSoluble = values["fiberSoluble"]
            d.fiberInsoluble = values["fiberInsoluble"]
            d.micros = values.filter { !coreKeys.contains($0.key) }

            // The label's own sense checks.
            if let f = d.fiber, let c = d.carbs, f > c { uncertain.formUnion(["fiber", "carbs"]) }
            if let sg = d.micros["sugar_g"], let c = d.carbs, sg > c { uncertain.insert("sugar_g") }
            if let sat = d.micros["sat_fat_g"], let f = d.fat, sat > f { uncertain.formUnion(["sat_fat_g", "fat"]) }
            if let sg = d.servingGrams, (d.protein ?? 0) + (d.carbs ?? 0) + (d.fat ?? 0) > sg * 1.05 {
                uncertain.insert("servingGrams")
            }
            if d.fiber == nil, let sol = d.fiberSoluble { d.fiber = sol + (d.fiberInsoluble ?? 0) }

            var notes: [String] = []
            if let n = s.note { notes.append(n) }
            if !converted.isEmpty {
                notes.append("converted from %DV: " + converted.map { NutritionLabelParser.displayName($0).lowercased() }.joined(separator: ", "))
            }
            d.notes = notes.isEmpty ? nil : notes.joined(separator: "; ")
            d.uncertain = uncertain
            return d
        }

        /// OCR often reads "12g" as "129". Strip the 9 when the amount is impossible for
        /// the serving, or when doing so makes the label's arithmetic add up.
        mutating func repairNineForG(servingGrams: Double?) {
            let macros = ["protein", "carbs", "fat", "fiber"]
            func stripped(_ key: String) -> Double? {
                guard bare.contains(key), let r = raw[key], r.count >= 2, r.hasSuffix("9"), !r.contains(".") else { return nil }
                return Double(r.dropLast())
            }
            for key in macros {
                if let sg = servingGrams, let v = values[key], v > sg, let fixed = stripped(key) {
                    values[key] = fixed
                    uncertain.insert(key)
                }
            }
            guard let kcal = values["kcal"], let p = values["protein"], let c = values["carbs"], let f = values["fat"] else { return }
            func consistent(_ p: Double, _ c: Double, _ f: Double) -> Bool {
                let a4 = p * 4 + c * 4 + f * 9
                let a2 = a4 - 2 * (values["fiber"] ?? 0)
                let tol = max(15, kcal * 0.15)
                return abs(kcal - a4) <= tol || abs(kcal - a2) <= tol
            }
            if consistent(p, c, f) { return }
            for key in ["protein", "carbs", "fat"] {
                guard let fixed = stripped(key) else { continue }
                let trial = (key == "protein" ? fixed : p, key == "carbs" ? fixed : c, key == "fat" ? fixed : f)
                if consistent(trial.0, trial.1, trial.2) {
                    values[key] = fixed
                    uncertain.insert(key)
                    return
                }
            }
        }
    }
}
