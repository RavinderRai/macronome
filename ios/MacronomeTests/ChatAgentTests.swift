import XCTest

/// The chat agent's tools, run against Ravi's real log and usual meals on a fresh day,
/// the loop with a scripted model, and how each service encodes tool calls.
@MainActor
final class ChatAgentTests: XCTestCase {
    private var repo: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    }

    /// A store holding the real log plus the usual meals, and the day after the last log.
    private func makeStore() throws -> (FoodStore, String) {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("agent-\(UUID().uuidString).jsonl")
        var data = try Data(contentsOf: repo.appendingPathComponent("food-log/events.jsonl"))
        data.append(Data("\n".utf8))
        data.append(try Data(contentsOf: repo.appendingPathComponent("food-log/meals.jsonl")))
        try data.write(to: url)
        let store = FoodStore(fileURL: url)
        let last = store.ledger.loggedDays.first ?? Clock.dayString()
        return (store, Clock.addDays(last, 1))
    }

    private func call(_ name: String, _ args: JSONValue) -> ToolCall {
        ToolCall(id: "c-\(name)", name: name, arguments: args.object ?? [:])
    }

    private func result(_ r: ToolResult) throws -> [String: JSONValue] {
        XCTAssertFalse(r.isError, r.content)
        return try XCTUnwrap(JSONValue.parse(r.content)?.object, r.content)
    }

    // MARK: tools

    func testLogsUsualMealsWithChangedAmountsAndComputesWhatsLeft() throws {
        let (store, day) = try makeStore()
        let tools = ChatTools(store: store, today: day)
        let before = store.ledger.entries.count
        let r = tools.run(call("log", [
            "items": [
                ["meal_id": "m-standard-breakfast", "slot": "breakfast"],
                ["meal_id": "m-potato-bowl", "slot": "lunch",
                 "changes": [["food_id": "83ae20", "qty": 310, "unit": "g"], ["food_id": "3fcb3b", "qty": 230, "unit": "g"]]],
            ],
        ]))
        _ = try result(r)
        let l = store.ledger
        XCTAssertEqual(l.entries.count, before + 7)
        let potato = try XCTUnwrap(l.entries(on: day).first { $0.foodID == "83ae20" })
        XCTAssertEqual(potato.qty, 310)
        XCTAssertEqual(potato.groupLabel, "Potato bowl")

        guard case .logged(let card) = try XCTUnwrap(tools.cards.first) else { return XCTFail("no log card") }
        XCTAssertEqual(card.groups.map(\.name), ["Standard breakfast", "Potato bowl"])
        XCTAssertEqual(card.entryIDs.count, 7)
        let eaten = l.totals(on: day).macros.kcal
        let target = try XCTUnwrap(l.targets(on: day).kcal)
        XCTAssertEqual(try XCTUnwrap(card.status.kcal), target - eaten, accuracy: 0.01)
        // The evening bowl is still to come, so it is held back.
        XCTAssertEqual(card.status.holdBack, "Evening bowl")
        let bowl = l.preview(try XCTUnwrap(l.meals["m-evening-bowl"]))
        XCTAssertEqual(try XCTUnwrap(card.status.afterHoldBackKcal), target - eaten - bowl.kcal, accuracy: 0.01)
    }

    func testNothingIsHeldBackOnceTheBowlIsEaten() throws {
        let (store, day) = try makeStore()
        let tools = ChatTools(store: store, today: day)
        XCTAssertNotNil(try result(tools.run(call("budget", [:])))["held_back"])
        _ = tools.run(call("log", ["items": [["meal_id": "full bowl"]]]))
        XCTAssertNil(try result(tools.run(call("budget", [:])))["held_back"])
    }

    func testEstimatesAndBackdatingLandOnTheRightDay() throws {
        let (store, day) = try makeStore()
        let tools = ChatTools(store: store, today: day)
        _ = try result(tools.run(call("log", [
            "items": [["meal_id": "m-evening-bowl", "day": "yesterday"],
                      ["food_id": "lettuce", "qty": 165, "unit": "g", "estimate": true]],
            "assumption": "I took “pull a ball” to mean your full bowl.",
        ])))
        let yesterday = Clock.addDays(day, -1)
        XCTAssertTrue(store.ledger.entries(on: yesterday).contains { $0.groupLabel == "Evening bowl" && $0.source == "chat" })
        let lettuce = try XCTUnwrap(store.ledger.entries(on: day).first { $0.label.lowercased().contains("lettuce") })
        XCTAssertEqual(lettuce.confidence, "estimate")
        guard case .logged(let card) = tools.cards.first else { return XCTFail() }
        XCTAssertEqual(card.groups.first?.title, "Yesterday")
        XCTAssertTrue(card.groups.last?.rows.first?.estimate ?? false)
        XCTAssertEqual(card.assumption, "I took “pull a ball” to mean your full bowl.")
    }

    func testCorrectionReplacesTheEntriesAndUndoPutsThemBack() throws {
        let (store, day) = try makeStore()
        let tools = ChatTools(store: store, today: day)
        let first = try result(tools.run(call("log", ["items": [["meal_id": "m-potato-bowl"]]])))
        let ids = (first["entry_ids"]?.array ?? []).compactMap(\.string)
        XCTAssertEqual(ids.count, 4)
        let potatoID = try XCTUnwrap(store.ledger.entries(on: day).first { $0.foodID == "83ae20" }?.id)
        _ = try result(tools.run(call("log", [
            "items": [["food_id": "83ae20", "qty": 300, "unit": "g"]], "replace_entry_ids": [.string(potatoID)], "slot": "lunch",
        ])))
        let potatoes = store.ledger.entries(on: day).filter { $0.foodID == "83ae20" }
        XCTAssertEqual(potatoes.map(\.qty), [300])

        guard case .logged(let fix) = tools.cards.last else { return XCTFail() }
        store.append(ChatCard.logged(fix).undoEvents(in: store.ledger))
        XCTAssertEqual(store.ledger.entries(on: day).filter { $0.foodID == "83ae20" }.map(\.qty), [350])
    }

    func testEditEntriesChangesAnAmountInPlace() throws {
        let (store, day) = try makeStore()
        let tools = ChatTools(store: store, today: day)
        _ = try result(tools.run(call("log", ["items": [["meal_id": "m-potato-bowl"]]])))
        let cauli = try XCTUnwrap(store.ledger.entries(on: day).first { $0.foodID == "3fcb3b" })
        _ = try result(tools.run(call("edit_entries", ["edits": [["entry_id": .string(cauli.id), "qty": 300]]])))
        let now = store.ledger.entries(on: day).filter { $0.foodID == "3fcb3b" }
        XCTAssertEqual(now.map(\.qty), [300])
        XCTAssertEqual(now.first?.groupID, cauli.groupID, "stays in the potato bowl")
        XCTAssertEqual(store.ledger.entries(on: day).count, 4)
        guard case .logged(let card) = tools.cards.last else { return XCTFail() }
        XCTAssertEqual(card.edited, true)
        store.append(ChatCard.logged(card).undoEvents(in: store.ledger))
        XCTAssertEqual(store.ledger.entries(on: day).filter { $0.foodID == "3fcb3b" }.map(\.qty), [80])
    }

    func testModelDefaultsAreHaikuForFastAndSonnetForSmart() {
        let c = TierConfig(kind: .anthropic)
        XCTAssertEqual(c.resolvedModel(fast: true), "claude-haiku-5-5")
        XCTAssertEqual(c.resolvedModel(fast: false), "claude-sonnet-5-5")
        XCTAssertEqual(TierConfig(kind: .anthropic, model: "claude-opus-5-5").resolvedModel(fast: true), "claude-opus-5-5")
        XCTAssertEqual(c.modelChoices.map(\.id), ["claude-haiku-5-5", "claude-sonnet-5-5", "claude-opus-5-5"])
    }

    func testOptionsCountTheHeldBackBowlAndFlagProtein() throws {
        let (store, day) = try makeStore()
        let tools = ChatTools(store: store, today: day)
        _ = tools.run(call("log", ["items": [["meal_id": "m-standard-breakfast"], ["meal_id": "m-potato-bowl"]]]))
        let out = try result(tools.run(call("show_options", [
            "title": "Dinner",
            "options": [
                ["label": "Nachos", "items": [["meal_id": "m-nachos"]]],
                ["label": "Chipotle sausage, 2 slices", "items": [["food_id": "chipotle", "qty": 1, "unit": "sausage"],
                                                                  ["food_id": "little big bread", "qty": 2, "unit": "slice"]]],
            ],
        ])))
        guard case .options(let card) = tools.cards.last else { return XCTFail("no options card") }
        let budget = try XCTUnwrap(card.budgetKcal)
        XCTAssertEqual(card.holdBack, "Evening bowl")
        for row in card.rows { XCTAssertEqual(try XCTUnwrap(row.spare), (budget - row.kcal).rounded(), accuracy: 1) }
        XCTAssertEqual(out["options"]?.array?.count, 2)
        XCTAssertEqual(store.ledger.entries(on: day).count, 7, "options write nothing")
    }

    func testSolveFindsPotatoAndCauliflowerThatFit() throws {
        let (store, day) = try makeStore()
        let tools = ChatTools(store: store, today: day)
        let out = try result(tools.run(call("solve", ["meal_id": "m-potato-bowl", "vary": ["83ae20", "3fcb3b"], "kcal_budget": 500])))
        let combos = try XCTUnwrap(out["amounts_in_grams"]?.array)
        XCTAssertFalse(combos.isEmpty)
        for c in combos { XCTAssertLessThanOrEqual(try XCTUnwrap(c.object?["kcal"]?.double), 500) }
        // More cauliflower leaves less room for potato.
        let potatoes = combos.compactMap { $0.object?["russet potato"]?.double }
        XCTAssertEqual(potatoes, potatoes.sorted(by: >))
    }

    func testTargetsAndMemoryWriteAndUndo() throws {
        let (store, day) = try makeStore()
        let tools = ChatTools(store: store, today: day)
        let was = store.ledger.standingTargets
        let out = try result(tools.run(call("set_targets", ["kcal": 1400, "protein": 150, "carbs": 120, "fat": 40])))
        XCTAssertEqual(store.ledger.standingTargets.kcal, 1400)
        XCTAssertNotNil(out["kcal_change_by_macro"])
        _ = try result(tools.run(call("remember", ["kind": "like", "text": "Salads come without bread."])))
        XCTAssertTrue(store.ledger.memoryNotes.contains { $0.value == "Salads come without bread." && $0.kind == "like" })

        for card in tools.cards { store.append(card.undoEvents(in: store.ledger)) }
        XCTAssertEqual(store.ledger.standingTargets.kcal, was.kcal)
        XCTAssertFalse(store.ledger.memoryNotes.contains { $0.value == "Salads come without bread." })
    }

    func testHistoryToolsReadTheRealLog() throws {
        let (store, day) = try makeStore()
        let tools = ChatTools(store: store, today: day)
        let freq = try result(tools.run(call("frequent", ["days": 30])))
        let foods = (freq["foods"]?.array ?? []).compactMap { $0.object?["food"]?.string }
        XCTAssertTrue(foods.contains { $0.contains("Beyond Yourself") })
        let hits = try result(tools.run(call("search_entries", ["query": "russet", "days": 30])))
        XCTAssertFalse((hits["entries"]?.array ?? []).isEmpty)
        let hist = try result(tools.run(call("history", ["start": .string(Clock.addDays(day, -7)), "end": .string(Clock.addDays(day, -1))])))
        XCTAssertEqual(hist["days"]?.array?.count, 7)
    }

    func testBadInputComesBackAsAToolError() throws {
        let (store, day) = try makeStore()
        let tools = ChatTools(store: store, today: day)
        XCTAssertTrue(tools.run(call("log", ["items": [["food_id": "dragonfruit"]]])).isError)
        XCTAssertTrue(tools.run(call("teleport", [:])).isError)
    }

    // MARK: numbers rule

    func testNumbersNotFromToolsAreCaught() {
        let allowed: Set<String> = ["609", "63", "1550"]
        XCTAssertEqual(ChatAgent.unsupportedNumbers(in: "609 left, 63 g protein, target 1,550.", allowed: allowed), [])
        XCTAssertEqual(ChatAgent.unsupportedNumbers(in: "That's about 612 kcal with 2 slices.", allowed: allowed), ["612"])
    }

    // MARK: loop

    func testLoopRunsToolsThenAnswers() async throws {
        let (store, day) = try makeStore()
        let tools = ChatTools(store: store, today: day)
        let model = ScriptedModel([
            AgentReply(text: "", calls: [ToolCall(id: "t1", name: "log", arguments: ["items": [["meal_id": "m-nachos"]]])], raw: nil, usage: ModelUsage()),
            AgentReply(text: "Logged. Fat is the tight one tonight.", calls: [], raw: nil, usage: ModelUsage()),
        ])
        let out = try await ChatAgent.run(provider: model, system: ["rules"], history: [.user("had nachos")], tools: tools) { _ in }
        XCTAssertEqual(out.text, "Logged. Fat is the tight one tonight.")
        XCTAssertEqual(out.cards.count, 1)
        XCTAssertEqual(model.requests.count, 2)
        guard case .results(let results) = try XCTUnwrap(model.requests.last?.items.last) else { return XCTFail("no tool results sent") }
        XCTAssertEqual(results.first?.callID, "t1")
        XCTAssertFalse(results.first?.isError ?? true)
    }

    func testLoopSendsBackAReplyWithMadeUpNumbersOnce() async throws {
        let (store, day) = try makeStore()
        let tools = ChatTools(store: store, today: day)
        let model = ScriptedModel([
            AgentReply(text: "Nachos would be 777 kcal.", calls: [], raw: nil, usage: ModelUsage()),
            AgentReply(text: "Nachos fit.", calls: [], raw: nil, usage: ModelUsage()),
        ])
        let out = try await ChatAgent.run(provider: model, system: ["rules"], history: [.user("can I have nachos")], tools: tools) { _ in }
        XCTAssertEqual(out.text, "Nachos fit.")
        guard case .user(let note) = try XCTUnwrap(model.requests.last?.items.last) else { return XCTFail() }
        XCTAssertTrue(note.contains("777"))
    }

    // MARK: encoding

    func testOpenAIToolEncodingRoundTrips() throws {
        let p = OpenAICompatibleProvider(baseURL: "https://openrouter.ai/api/v1", model: "x", apiKey: "k")
        let reply = try OpenAICompatibleProvider.parseAgent(Data(#"""
        {"choices":[{"message":{"role":"assistant","content":null,"tool_calls":[{"id":"call_1","type":"function",
        "function":{"name":"budget","arguments":"{\"day\":\"today\"}"}}]}}],"usage":{"prompt_tokens":10,"completion_tokens":3}}
        """#.utf8))
        XCTAssertEqual(reply.calls, [ToolCall(id: "call_1", name: "budget", arguments: ["day": "today"])])
        let body = p.agentBody(AgentRequest(system: ["s"], items: [
            .user("hi"), .assistant(text: reply.text, calls: reply.calls, raw: reply.raw),
            .results([ToolResult(callID: "call_1", name: "budget", content: "{}")]),
        ], tools: ChatAgent.specs))
        let messages = try XCTUnwrap(body["messages"] as? [[String: Any]])
        XCTAssertEqual(messages.map { $0["role"] as? String }, ["system", "user", "assistant", "tool"])
        XCTAssertNotNil(messages[2]["tool_calls"])
        XCTAssertEqual(messages[3]["tool_call_id"] as? String, "call_1")
        XCTAssertEqual((body["tools"] as? [Any])?.count, ChatAgent.specs.count)
        XCTAssertNoThrow(try JSONSerialization.data(withJSONObject: body))
    }

    func testAnthropicKeepsThinkingBlocksAndBatchesResults() throws {
        let p = AnthropicProvider(model: "claude-haiku-5-5", apiKey: "k")
        let reply = try AnthropicProvider.parseAgent(Data(#"""
        {"content":[{"type":"thinking","thinking":"","signature":"sig"},{"type":"text","text":"Checking."},
        {"type":"tool_use","id":"tu_1","name":"budget","input":{}},{"type":"tool_use","id":"tu_2","name":"frequent","input":{"days":7}}],
        "stop_reason":"tool_use","usage":{"input_tokens":5,"output_tokens":2}}
        """#.utf8))
        XCTAssertEqual(reply.calls.map(\.id), ["tu_1", "tu_2"])
        XCTAssertEqual(reply.calls.last?.arguments["days"]?.double, 7)
        let body = p.agentBody(AgentRequest(system: ["stable", "day"], items: [
            .user("hi"), .assistant(text: reply.text, calls: reply.calls, raw: reply.raw),
            .results([ToolResult(callID: "tu_1", name: "budget", content: "{}"),
                      ToolResult(callID: "tu_2", name: "frequent", content: "Error: no", isError: true)]),
        ], tools: ChatAgent.specs), effort: true)
        let messages = try XCTUnwrap(body["messages"] as? [[String: Any]])
        XCTAssertEqual(messages.map { $0["role"] as? String }, ["user", "assistant", "user"])
        let assistant = try XCTUnwrap(messages[1]["content"] as? [[String: Any]])
        XCTAssertEqual(assistant.first?["type"] as? String, "thinking")
        XCTAssertEqual(assistant.first?["signature"] as? String, "sig")
        let results = try XCTUnwrap(messages[2]["content"] as? [[String: Any]])
        XCTAssertEqual(results.compactMap { $0["tool_use_id"] as? String }, ["tu_1", "tu_2"])
        XCTAssertEqual(results.last?["is_error"] as? Bool, true)
        XCTAssertNoThrow(try JSONSerialization.data(withJSONObject: body))
    }
}

/// Replies in order and records every request.
private final class ScriptedModel: ModelProvider, @unchecked Sendable {
    var replies: [AgentReply]
    private(set) var requests: [AgentRequest] = []
    init(_ replies: [AgentReply]) { self.replies = replies }

    var usageKey: String { "scripted" }
    var acceptsImages: Bool { false }
    var supportsTools: Bool { true }
    func complete(_ request: ModelRequest) async throws -> ModelReply { throw ProviderError.unsupported("") }
    func respond(_ request: AgentRequest) async throws -> AgentReply {
        requests.append(request)
        guard !replies.isEmpty else { throw ProviderError.badResponse("script ran out") }
        return replies.removeFirst()
    }
}
