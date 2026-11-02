import Foundation

/// The chat agent: one loop, the same for every service. Send the context and tools,
/// run whatever tools the model asks for on the phone, send the results back, repeat
/// until it answers. A reply that quotes a number no tool or context produced is sent
/// back once to be fixed.
@MainActor
enum ChatAgent {
    static let maxRounds = 8

    struct Outcome {
        var text: String
        var cards: [ChatCard]
    }

    static func run(provider: any ModelProvider, system: [String], history: [AgentItem], tools: ChatTools,
                    record: (ModelUsage) -> Void) async throws -> Outcome {
        for part in system { tools.allowNumbers(in: part) }
        for case .user(let t) in history { tools.allowNumbers(in: t) }
        var items = history
        var checked = false
        var lastText = ""
        for _ in 0..<maxRounds {
            let reply = try await provider.respond(AgentRequest(system: system, items: items, tools: specs))
            record(reply.usage)
            items.append(.assistant(text: reply.text, calls: reply.calls, raw: reply.raw))
            lastText = reply.text
            if reply.calls.isEmpty {
                let bad = unsupportedNumbers(in: reply.text, allowed: tools.numbers)
                if bad.isEmpty || checked { return Outcome(text: clean(reply.text), cards: tools.cards) }
                checked = true
                items.append(.user("(App check, not from Ravi) These numbers in your reply didn't come from a tool result "
                    + "or the context: \(bad.joined(separator: ", ")). Get them with preview or budget, or leave them out, "
                    + "and give the reply again. Don't log anything twice."))
                continue
            }
            items.append(.results(reply.calls.map(tools.run)))
        }
        let text = clean(lastText)
        return Outcome(text: text.isEmpty ? "That took too many steps. Try asking in smaller pieces." : text, cards: tools.cards)
    }

    /// Numbers of 5 or more in the text that are not in `allowed` (as written, or rounded).
    static func unsupportedNumbers(in text: String, allowed: Set<String>) -> [String] {
        var out: [String] = []
        for m in text.matches(of: /\d[\d,]*(\.\d+)?/) {
            let raw = String(text[m.range])
            let s = raw.replacingOccurrences(of: ",", with: "")
            guard let v = Double(s), v >= 5 else { continue }
            if allowed.contains(s) || allowed.contains(String(Int(v.rounded()))) || allowed.contains(Format.trim(v)) { continue }
            if !out.contains(raw) { out.append(raw) }
        }
        return out
    }

    private static func clean(_ s: String) -> String { s.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// Earlier turns as plain text; cards become one-line summaries.
    static func history(_ messages: [ChatMessage], limit: Int = 24) -> [AgentItem] {
        var out: [AgentItem] = []
        for m in messages.suffix(limit) {
            switch m.role {
            case .user:
                out.append(.user(m.text))
            case .assistant:
                guard !out.isEmpty else { continue }
                var text = m.text
                let extra = m.cards.map(\.summary) + (m.options.isEmpty ? [] : ["[Options: " + m.options.map(\.title).joined(separator: "; ") + "]"])
                if !extra.isEmpty { text += (text.isEmpty ? "" : "\n") + extra.joined(separator: "\n") }
                if !text.isEmpty { out.append(.assistant(text: text, calls: [], raw: nil)) }
            case .system:
                continue
            }
        }
        return out
    }

    // MARK: - prompt

    static let rules = """
    You are the chat inside Macronome, Ravi's food log. He mostly talks to you by voice: to log what he ate, \
    plan meals, try what-ifs, and change targets. You act through tools; the app shows their results as cards.

    Logging
    - When he says he ate something, call log straight away. Never ask him to confirm. Usual meals go by \
    meal_id; changed amounts go in changes (qty 0 removes a part). Several meals or days in one message: one \
    log call, with day and slot on each item.
    - Speech-to-text mishears ("pull a ball" or "foldable" for "full bowl", "serial" for "cereal"). Work out \
    what he meant from his foods, meals and routine, log it, and say what you assumed in the log call's \
    assumption field, in one line ("I took “pull a ball” to mean your full bowl."). Mishearings are noise: \
    never remember them.
    - Ask before logging only when an amount is implausible (several times his usual). Otherwise log.
    - Amounts he guessed rather than weighed get estimate: true.
    - A different amount for something already logged ("actually it was 13 g of seasoning", or "300 grams" \
    after "the cauliflower isn't cooked yet, I'll tell you the weight"): call edit_entries. When a part's \
    weight comes later, log it now at the meal's usual amount and edit it when he gives the number.
    - A different food ("I said full bowl, not the snack bowl"): call log with the right one and \
    replace_entry_ids set to the entries being replaced. Today's entry ids are in the context; \
    search_entries finds older ones.
    - "Log the bowl now, I'll have it later": log it now.

    Planning
    - The held-back meal (his evening bowl) stays out of every budget. It can shrink, but is never dropped or \
    swapped. Budgets, previews and options already hold it back: use left_after_held_back.
    - "What should I have?": call show_options with 3 to 5 options built from his foods and usual meals. Then \
    write one line on the trade-off that matters today (which one hits protein, what is tight, what doesn't fit \
    and by how much). Don't list the options again; the card does.
    - What-ifs ("with 2 slices or none?"): call show_options with one row per variant and a title for what \
    changes ("Bread"). "How much potato and cauliflower can I have?": call solve.
    - "Had it", "I had exactly that": log the option being discussed, with any changes he gives.

    Numbers
    - Never do arithmetic. Every number you write must come from a tool result or the context below. Call \
    preview or budget when you need another one.
    - After a log the card shows what's left; add at most one line, and only if something matters (a macro \
    that is tight, a day that lands over).

    Memory and targets
    - When he states a preference, rule or fact worth keeping ("I can't taste the nutritional yeast", "no bread \
    with salads"), call remember. kind: rule (applies to every plan), meal (about a usual meal), like (a \
    preference or verdict), fact (diet, allergies, equipment). Don't remember one-off things.
    - Target changes ("week nine: 1550, protein 155, take the rest from carbs, fat down a little"): work out \
    the grams, call set_targets, and say where the cut came from using kcal_change_by_macro.

    Style: short and plain. One-line answers to one-line questions. No headings, no bullet lists, no \
    repeating the plan back. Food questions on the side ("no russets, white or yellow?") are welcome.
    """

    static func system(ledger: Ledger, tools: ChatTools) -> [String] {
        let stable = [
            rules,
            ChatPrompt.notesSection(ledger: ledger, compact: false),
            ChatPrompt.mealsSection(ledger: ledger),
            ChatPrompt.foodsSection(ledger: ledger, compact: true),
        ].filter { !$0.isEmpty }.joined(separator: "\n\n")
        var day = ChatPrompt.dayContext(ledger: ledger, day: tools.today, now: tools.now)
        let entries = ledger.entries(on: tools.today)
        if !entries.isEmpty {
            day += "\n\nToday's entries (entry_id | slot | food | amount | meal):\n" + entries.map { e in
                "- \(e.id) | \(e.meal?.rawValue ?? "-") | \(e.label) | \(e.amountText) | \(e.groupLabel ?? "-")"
            }.joined(separator: "\n")
        }
        day += "\n\nBudget now (from the budget tool):\n" + tools.budget(day: tools.today).jsonText
        return [stable, day]
    }

    // MARK: - tools

    private static func schema(_ props: [String: JSONValue], required: [String] = []) -> JSONValue {
        .object(["type": "object", "properties": .object(props), "required": .array(required.map { .string($0) })])
    }

    private static let dayProp: JSONValue = ["type": "string", "description": "today, yesterday, tomorrow or YYYY-MM-DD. Default today."]
    private static let slotProp: JSONValue = ["type": "string", "enum": ["breakfast", "lunch", "dinner", "snack"]]

    private static let item: JSONValue = schema([
        "meal_id": ["type": "string", "description": "A usual meal's id. Its parts are used at their default amounts unless changed."],
        "changes": [
            "type": "array",
            "description": "For a meal: parts to change, add (a food not in it) or remove (qty 0).",
            "items": schema(["food_id": ["type": "string"], "qty": ["type": "number"], "unit": ["type": "string"]],
                            required: ["food_id", "qty"]),
        ],
        "food_id": ["type": "string", "description": "A food's id from the library."],
        "qty": ["type": "number"],
        "unit": ["type": "string", "description": "g, ml, serving, or the food's serving label (cup, scoop, slice, can)."],
        "label": ["type": "string", "description": "A name for the item; required for a one-off estimate."],
        "kcal": ["type": "number", "description": "One-off estimate only, with protein, carbs and fat."],
        "protein": ["type": "number"], "carbs": ["type": "number"], "fat": ["type": "number"],
        "estimate": ["type": "boolean", "description": "The amount was guessed, not weighed."],
        "estimated_food_ids": ["type": "array", "items": ["type": "string"], "description": "For a meal: the parts whose amounts were guessed."],
        "day": dayProp,
        "slot": slotProp,
    ])

    static let specs: [ToolSpec] = [
        ToolSpec(name: "budget", description: "What's left on a day for calories, protein, carbs and fat, and what's left once the held-back evening bowl is counted.",
                 parameters: schema(["day": dayProp])),
        ToolSpec(name: "preview", description: "Totals for some foods or meals and what would be left after eating them. Writes nothing. Use for any number you need.",
                 parameters: schema(["items": ["type": "array", "items": item], "day": dayProp], required: ["items"])),
        ToolSpec(name: "show_options", description: "Show options as a table card: kcal, protein, and spare or over against the budget with the evening bowl held back. For meal ideas and what-ifs.",
                 parameters: schema([
                     "title": ["type": "string", "description": "Column header: Dinner, Snack, Bread…"],
                     "options": ["type": "array", "items": schema(["label": ["type": "string"], "items": ["type": "array", "items": item]],
                                                                  required: ["label", "items"])],
                     "day": dayProp,
                 ], required: ["options"])),
        ToolSpec(name: "solve", description: "Amounts (in grams) of one or two parts of a usual meal that fit the budget, the rest at defaults.",
                 parameters: schema([
                     "meal_id": ["type": "string"],
                     "vary": ["type": "array", "items": ["type": "string"], "description": "One or two food ids from the meal."],
                     "kcal_budget": ["type": "number", "description": "Default: what's left with the evening bowl held back."],
                     "day": dayProp,
                 ], required: ["meal_id", "vary"])),
        ToolSpec(name: "log", description: "Log what he ate. Shows a Logged card with what's left. Use replace_entry_ids to correct earlier entries.",
                 parameters: schema([
                     "items": ["type": "array", "items": item],
                     "label": ["type": "string", "description": "Name for loose foods eaten as one dish, e.g. Field Roast + Gusta salad."],
                     "day": dayProp,
                     "slot": slotProp,
                     "assumption": ["type": "string", "description": "One line on anything you assumed, e.g. a misheard word."],
                     "replace_entry_ids": ["type": "array", "items": ["type": "string"]],
                 ], required: ["items"])),
        ToolSpec(name: "edit_entries", description: "Change the amount of entries already logged: a weight given later, or a corrected amount. Shows an Updated card.",
                 parameters: schema([
                     "edits": ["type": "array", "items": schema([
                         "entry_id": ["type": "string"], "qty": ["type": "number"],
                         "unit": ["type": "string", "description": "Default: the entry's unit."],
                         "estimate": ["type": "boolean"],
                     ], required: ["entry_id", "qty"])],
                     "assumption": ["type": "string"],
                 ], required: ["edits"])),
        ToolSpec(name: "delete_entries", description: "Remove entries from the log.",
                 parameters: schema(["entry_ids": ["type": "array", "items": ["type": "string"]]], required: ["entry_ids"])),
        ToolSpec(name: "find", description: "Search his foods and usual meals by name.",
                 parameters: schema(["query": ["type": "string"]], required: ["query"])),
        ToolSpec(name: "history", description: "Daily totals and targets between two days, with the average.",
                 parameters: schema(["start": dayProp, "end": dayProp])),
        ToolSpec(name: "search_entries", description: "When he ate a food or meal, newest first.",
                 parameters: schema(["query": ["type": "string"], "days": ["type": "number", "description": "How far back. Default 30."]])),
        ToolSpec(name: "frequent", description: "His most eaten meals and foods, with typical amounts.",
                 parameters: schema(["days": ["type": "number", "description": "Default 30."], "slot": slotProp])),
        ToolSpec(name: "set_targets", description: "Set new daily targets. Shows old and new on a card.",
                 parameters: schema(["kcal": ["type": "number"], "protein": ["type": "number"], "carbs": ["type": "number"],
                                     "fat": ["type": "number"]])),
        ToolSpec(name: "remember", description: "Keep a preference, rule or fact for every future chat. Shows a Remembered card with Undo.",
                 parameters: schema([
                     "kind": ["type": "string", "enum": ["rule", "meal", "like", "fact"]],
                     "text": ["type": "string", "description": "One plain sentence."],
                     "key": ["type": "string", "description": "An existing memory's key, to replace it."],
                 ], required: ["kind", "text"])),
        ToolSpec(name: "forget", description: "Remove something remembered, by its key.",
                 parameters: schema(["key": ["type": "string"]], required: ["key"])),
    ]
}
