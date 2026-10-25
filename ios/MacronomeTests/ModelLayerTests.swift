import XCTest

/// The model layer without a network: prompts carry the day and the notes, replies are
/// parsed defensively, and every number comes from the ledger rather than the model.
final class ModelLayerTests: XCTestCase {
    private let day = "2026-10-24"

    private func ledger() -> Ledger {
        var events: [Event] = [
            Commands.setProfile("target_kcal", "1700"),
            Commands.setProfile("target_protein", "165"),
            Commands.setProfile("target_carbs", "159"),
            Commands.setProfile("target_fat", "45"),
            Commands.setProfile("diet", "vegan"),
            Commands.setProfile("snack_definition", "A snack is zero prep, under two minutes, no pan."),
            Commands.setProfile("prep_times", "Air frying potatoes takes ~20 min and is never quick."),
        ]
        events.append(Event.new("food_add", [
            "id": "pot001", "name": "Russet potato", "basis": "100g", "kcal": 79, "protein": 2.1, "carbs": 18, "fat": 0.1,
            "fiber": 1.3,
        ]))
        events.append(Event.new("food_add", [
            "id": "gus002", "name": "Gusta veggie ground", "basis": "serving", "serving_grams": 55, "serving_label": "serving",
            "kcal": 110, "protein": 17, "carbs": 4, "fat": 3,
        ]))
        events.append(Commands.setMeal(UsualMeal(id: "potato_bowl", name: "Potato bowl", aliases: ["poutine"], slot: .lunch,
                                                 components: [.init(foodID: "pot001", qty: 350, unit: "g"),
                                                              .init(foodID: "gus002", qty: 2, unit: "serving")], note: nil)))
        let l = Ledger(events: events)
        let gus = l.foods["gus002"]!
        events.append(try! Commands.log(gus, qty: 1, unit: "serving", day: day, meal: .breakfast))
        return Ledger(events: events)
    }

    // MARK: prompt

    func testPromptCarriesTargetsNotesAndLibrary() {
        let l = ledger()
        let parts = ChatPrompt.system(ledger: l, day: day, now: Clock.date(fromDay: day)!)
        XCTAssertEqual(parts.count, 2)
        let stable = parts[0], dayPart = parts[1]
        XCTAssertTrue(stable.contains("snack_definition: A snack is zero prep"))
        XCTAssertTrue(stable.contains("prep_times: Air frying potatoes"))
        XCTAssertTrue(stable.contains("diet: vegan"))
        XCTAssertTrue(stable.contains("pot001 | Russet potato"))
        XCTAssertTrue(stable.contains("potato_bowl | Potato bowl"))
        XCTAssertTrue(stable.contains("Never do arithmetic"))
        // Targets and what is left, as computed by the ledger.
        XCTAssertTrue(dayPart.contains("Calories: eaten 110 kcal, target 1,700, 1,590 left"), dayPart)
        XCTAssertTrue(dayPart.contains("Protein: eaten 17 g, target 165, 148 left"), dayPart)
        // The stable part must not change with the day, or the prompt cache is useless.
        XCTAssertFalse(stable.contains(day))
    }

    func testInterpreterLibraryHasIdsAndUnits() {
        let lib = InterpreterPrompt.library(ledger())
        XCTAssertTrue(lib.contains("pot001 | Russet potato | g"))
        XCTAssertTrue(lib.contains("gus002 | Gusta veggie ground | 1 serving = 55 g"))
        XCTAssertTrue(lib.contains("potato_bowl | Potato bowl | aka poutine"))
    }

    // MARK: reply parsing

    func testParsesFencedJSONAndRecomputesMacros() {
        let l = ledger()
        let raw = """
        ```json
        {"text": "You have 1,590 left.", "options": [{"title": "Potato bowl, 300 g potato", "detail": "About 20 min · air fryer",
         "meal_id": "potato_bowl", "slot": "dinner", "kcal": 9999, "protein": 1,
         "components": [{"food_id": "pot001", "qty": "300", "unit": "g"}, {"food_id": "gus002", "qty": 2, "unit": "serving"}]}]}
        ```
        """
        let m = ChatReplyParser.parse(raw, ledger: l)
        XCTAssertEqual(m.text, "You have 1,590 left.")
        XCTAssertEqual(m.options.count, 1)
        let o = m.options[0]
        XCTAssertEqual(o.slot, .dinner)
        XCTAssertEqual(o.mealID, "potato_bowl")
        XCTAssertEqual(o.components.count, 2)
        // The model's 9999 kcal is ignored: 300 g potato + 2 servings Gusta, from the ledger.
        let expected = l.preview(l.foods["pot001"]!, qty: 300, unit: "g")! + l.preview(l.foods["gus002"]!, qty: 2, unit: "serving")!
        XCTAssertEqual(o.kcal, expected.kcal, accuracy: 0.001)
        XCTAssertEqual(o.protein, expected.protein, accuracy: 0.001)
        XCTAssertEqual(o.protein, 2.1 * 3 + 34, accuracy: 0.001)
    }

    func testDropsUnknownFoodIdsAndEmptyOptions() {
        let l = ledger()
        let raw = """
        Here you go: {"text": "Two ideas.", "options": [
          {"title": "Mixed", "components": [{"food_id": "pot001", "qty": 200, "unit": "g"}, {"food_id": "zzz999", "qty": 1, "unit": "serving"}]},
          {"title": "Imaginary", "components": [{"food_id": "nope42", "qty": 1, "unit": "serving"}]},
          {"title": "Bad unit", "components": [{"food_id": "gus002", "qty": 1, "unit": "bucket"}]}
        ]} Enjoy.
        """
        let m = ChatReplyParser.parse(raw, ledger: l)
        XCTAssertEqual(m.text, "Two ideas.")
        XCTAssertEqual(m.options.map(\.title), ["Mixed"])
        XCTAssertEqual(m.options[0].components.map(\.foodID), ["pot001"])
        XCTAssertEqual(m.options[0].kcal, l.preview(l.foods["pot001"]!, qty: 200, unit: "g")!.kcal, accuracy: 0.001)
    }

    func testMealIdWithoutComponentsUsesTheMealDefaults() {
        let l = ledger()
        let m = ChatReplyParser.parse(#"{"text": "The bowl fits.", "options": [{"title": "Potato bowl", "meal_id": "potato_bowl"}]}"#, ledger: l)
        XCTAssertEqual(m.options.count, 1)
        XCTAssertEqual(m.options[0].kcal, l.preview(l.meals["potato_bowl"]!).kcal, accuracy: 0.001)
    }

    func testPlainTextFallback() {
        let m = ChatReplyParser.parse("You're at 110 so far, plenty of room for dinner.", ledger: ledger())
        XCTAssertEqual(m.text, "You're at 110 so far, plenty of room for dinner.")
        XCTAssertTrue(m.options.isEmpty)
        let fenced = ChatReplyParser.parse("```\nJust text in a fence\n```", ledger: ledger())
        XCTAssertEqual(fenced.text, "Just text in a fence")
    }

    // MARK: interpreter

    func testInterpreterValidatesIds() {
        let l = ledger()
        let raw = """
        {"items": [
          {"phrase": "150 g potato", "food_id": "pot001", "qty": 150, "unit": "g"},
          {"phrase": "the poutine", "meal_id": "poutine"},
          {"phrase": "a burrito", "food_id": "fake01", "label": "Burrito", "kcal": 700, "protein": 30, "carbs": 80, "fat": 25},
          {"phrase": "some ground", "food_id": "gus002", "qty": 2, "unit": "bucket"},
          {"phrase": "mystery", "food_id": "fake02"}
        ]}
        """
        let items = InterpreterPrompt.validate(InterpreterPrompt.parse(raw), text: "lunch", ledger: l)
        XCTAssertEqual(items.count, 5)
        XCTAssertEqual(items[0].foodID, "pot001")
        XCTAssertEqual(items[0].unit, "g")
        XCTAssertEqual(items[1].mealID, "potato_bowl", "aliases resolve to the meal")
        XCTAssertNil(items[2].foodID)
        XCTAssertEqual(items[2].estimate?.kcal, 700)
        XCTAssertEqual(items[3].unit, "serving", "an unloggable unit falls back to the food's own")
        XCTAssertFalse(items[4].isResolved)
    }

    // MARK: providers (request shape only, no network)

    func testAnthropicBodyCachesStablePartAndAttachesImages() {
        let p = AnthropicProvider(model: "claude-haiku-5-5", apiKey: "k")
        XCTAssertEqual(p.url?.absoluteString, "https://api.anthropic.com/v1/messages")
        let r = ModelRequest(system: ["stable", "day"], messages: [ModelMessage(role: .assistant, text: "hi"),
                                                                   ModelMessage(role: .user, text: "read this")],
                             images: [Data([1, 2, 3])])
        let body = p.body(r, effort: true)
        let system = body["system"] as! [[String: Any]]
        XCTAssertNotNil(system[0]["cache_control"])
        XCTAssertNil(system[1]["cache_control"])
        let messages = body["messages"] as! [[String: Any]]
        XCTAssertEqual(messages.count, 1, "a leading assistant turn is dropped")
        let content = messages[0]["content"] as! [[String: Any]]
        XCTAssertEqual(content.first?["type"] as? String, "image")
        XCTAssertNil(body["temperature"])
    }

    func testOpenAIBodyAndUsageParsing() throws {
        let p = OpenAICompatibleProvider(baseURL: "https://openrouter.ai/api/v1/", model: "m", apiKey: "k")
        let body = p.body(ModelRequest(system: ["a", "b"], messages: [ModelMessage(role: .user, text: "x")], jsonMode: true),
                          options: .init(json: true))
        let messages = body["messages"] as! [[String: Any]]
        XCTAssertEqual(messages[0]["content"] as? String, "a\n\nb")
        XCTAssertNotNil(body["response_format"])
        let reply = try OpenAICompatibleProvider.parse(Data(#"{"choices":[{"message":{"content":"ok"}}],"usage":{"prompt_tokens":12,"completion_tokens":3}}"#.utf8))
        XCTAssertEqual(reply.text, "ok")
        XCTAssertEqual(reply.usage, ModelUsage(input: 12, output: 3, cached: 0))
        XCTAssertEqual(p.usageKey, "openrouter.ai · m")
    }

    func testFriendlyHTTPErrors() {
        let e = ProviderError.friendly(status: 401, body: Data(#"{"error":{"message":"invalid x-api-key"}}"#.utf8))
        XCTAssertEqual(e, .http(401, "The key was refused. Check the API key. invalid x-api-key"))
        if case .http(429, let s) = ProviderError.friendly(status: 429, body: Data()) {
            XCTAssertTrue(s.contains("Rate limited"))
        } else { XCTFail() }
    }

    func testUsageLogSumsPerDay() {
        var log = UsageLog()
        log.record("A", ModelUsage(input: 100, output: 10), day: day)
        log.record("A", ModelUsage(input: 50, output: 5, cached: 40), day: day)
        log.record("B", ModelUsage(input: 1, output: 1), day: Clock.addDays(day, -1))
        XCTAssertEqual(log.on(day).first?.counts, UsageCounts(requests: 2, input: 150, output: 15, cached: 40))
        XCTAssertEqual(log.total(lastDays: 7, today: day).requests, 3)
        XCTAssertEqual(UsageLog.tokens(8200), "8.2k")
    }
}
