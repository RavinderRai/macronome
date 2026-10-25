import XCTest

/// The offline parser against Ravi's real library: food-log/events.jsonl plus the usual
/// meals in food-log/meals.jsonl.
final class LocalLogInterpreterTests: XCTestCase {
    private static let ledger: Ledger = {
        let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        var data = (try? Data(contentsOf: repo.appendingPathComponent("food-log/events.jsonl"))) ?? Data()
        data.append(Data("\n".utf8))
        data.append((try? Data(contentsOf: repo.appendingPathComponent("food-log/meals.jsonl"))) ?? Data())
        return Ledger(events: EventCodec.decodeLines(data))
    }()

    private var ledger: Ledger { Self.ledger }
    private let parser = LocalLogInterpreter()

    private func parse(_ text: String) -> LogParse { parser.parse(text, ledger: ledger) }
    private func draft(_ text: String) -> LogDraft {
        let p = parse(text)
        return LogDraft(items: p.items, slot: p.slot, ledger: ledger, readings: p.readings)
    }

    func testFixturesLoaded() {
        XCTAssertNotNil(ledger.meals["m-potato-bowl"])
        XCTAssertNotNil(ledger.foods["3fcb3b"])
    }

    // MARK: usual meals

    func testPotatoBowlWithCauliflowerOverride() {
        let p = parse("had the potato bowl with a hundred grams of cauliflower")
        XCTAssertEqual(p.items.count, 2)
        XCTAssertEqual(p.items[0].mealID, "m-potato-bowl")
        XCTAssertEqual(p.items[1].foodID, "3fcb3b")
        XCTAssertEqual(p.items[1].qty, 100)
        XCTAssertEqual(p.items[1].unit, "g")

        let d = draft("had the potato bowl with a hundred grams of cauliflower")
        XCTAssertEqual(d.meals.map(\.id), ["m-potato-bowl"])
        XCTAssertEqual(d.lines.count, 4)
        let cauli = d.lines.first { $0.food.id == "3fcb3b" }
        XCTAssertEqual(cauli?.qty, 100)
        XCTAssertEqual(cauli?.unit, "g")
        XCTAssertTrue(cauli?.changedFromDefault ?? false)
        let potato = d.lines.first { $0.food.id == "83ae20" }
        XCTAssertEqual(potato?.qty, 350)
        XCTAssertFalse(potato?.changedFromDefault ?? true)
        XCTAssertEqual(d.label(ledger: ledger), "Potato bowl")
        XCTAssertTrue(d.unresolved.isEmpty)
    }

    func testOverridesWithoutUnitsOrCommas() {
        let d = draft("Had the potato bowl, 350 of potato and a hundred cauli")
        XCTAssertEqual(d.lines.first { $0.food.id == "83ae20" }?.qty, 350)
        XCTAssertEqual(d.lines.first { $0.food.id == "3fcb3b" }?.qty, 100)
        XCTAssertEqual(d.lines.first { $0.food.id == "3fcb3b" }?.unit, "g")
        XCTAssertEqual(d.lines.count, 4)
    }

    func testStandardBreakfast() {
        let d = draft("standard breakfast")
        XCTAssertEqual(d.meals.map(\.id), ["m-standard-breakfast"])
        XCTAssertEqual(d.lines.map(\.food.id), ["306de6", "82f120", "4447f3"])
        XCTAssertEqual(d.resolvedSlot(at: date(hour: 8)), .breakfast)
        let events = d.events(ledger: ledger, source: "voice", slot: .breakfast, label: d.label(ledger: ledger))
        XCTAssertEqual(events.count, 3)
        XCTAssertEqual(Set(events.compactMap { $0.string("group_id") }).count, 1)
        XCTAssertEqual(events.first?.string("group_label"), "Standard breakfast")
        XCTAssertEqual(events.first?.string("source"), "voice")
    }

    func testMisheardBowlOfCereal() {
        for text in ["a full bold of serial", "Pull a ball of serial before bed"] {
            let p = parse(text)
            XCTAssertEqual(p.items.count, 1, text)
            XCTAssertEqual(p.items.first?.mealID, "m-evening-bowl", text)
            XCTAssertEqual(p.readings.values.first, "Evening bowl", text)
        }
    }

    // MARK: foods

    func testTwoFoodsInOneUtterance() {
        let text = "two scoops of cookie dough protein and a cup of almond milk"
        let p = parse(text)
        XCTAssertEqual(p.items.map(\.foodID), ["82f120", "4447f3"])
        XCTAssertEqual(p.items.map(\.qty), [2, 1])
        XCTAssertEqual(p.items.map(\.unit), ["scoop", "cup"])

        let d = draft(text)
        XCTAssertEqual(d.label(ledger: ledger), "Cookie dough protein and almond milk")
        let events = d.events(ledger: ledger, source: "text", slot: .snack, label: d.label(ledger: ledger))
        XCTAssertEqual(events.count, 2)
        XCTAssertEqual(Set(events.compactMap { $0.string("group_id") }).count, 1)
    }

    func testGramsOfTofu() {
        let p = parse("150 grams of tofu")
        XCTAssertEqual(p.items.first?.foodID, "484d75")
        XCTAssertEqual(p.items.first?.qty, 150)
        XCTAssertEqual(p.items.first?.unit, "g")
        let d = draft("150 grams of tofu")
        XCTAssertEqual(d.lines.first?.macros?.kcal ?? 0, ledger.preview(ledger.foods["484d75"]!, qty: 150, unit: "g")!.kcal, accuracy: 0.001)
    }

    func testMeatballsCountedByTheirServingLabel() {
        let p = parse("3 meatballs")
        XCTAssertEqual(p.items.first?.foodID, "f8325c")
        XCTAssertEqual(p.items.first?.qty, 3)
        let d = draft("3 meatballs")
        XCTAssertEqual(d.lines.first?.qty, 3)
        XCTAssertNotNil(d.lines.first?.macros)
        XCTAssertEqual(try Ledger.resolveAmount(ledger.foods["f8325c"]!, qty: 3, unit: d.lines[0].unit).factor, 3)
    }

    func testSoundAlikeBrand() {
        let p = parse("two servings of gusto")
        XCTAssertEqual(p.items.first?.foodID, "bf697f")
        XCTAssertEqual(p.items.first?.qty, 2)
    }

    func testAmbiguousProteinPicksOneAndOffersTheOther() {
        let p = parse("a scoop of protein")
        let pick = p.items.first?.foodID
        XCTAssertTrue(["82f120", "a21abf"].contains(pick ?? ""))
        XCTAssertFalse(p.items.first?.alternatives.isEmpty ?? true)
    }

    func testUnknownFoodIsUnresolved() {
        let p = parse("a big mac and 150 grams of tofu")
        XCTAssertEqual(p.unresolved.map(\.label), ["big mac"])
        XCTAssertEqual(p.items.last?.foodID, "484d75")
    }

    func testSlotFromWords() {
        let p = parse("for lunch I had 150 grams of tofu")
        XCTAssertEqual(p.slot, .lunch)
        XCTAssertEqual(p.items.first?.foodID, "484d75")
        XCTAssertNil(parse("snack bowl").slot)
        XCTAssertEqual(parse("snack bowl").items.first?.mealID, "m-snack-bowl")
    }

    func testWordsOutsideTheLibraryDoNotGrabARandomFood() {
        for text in ["had a coffee", "a banana", "some chocolate"] {
            let p = parse(text)
            XCTAssertTrue(p.items.allSatisfy { !$0.isResolved }, "\(text) -> \(p.items.map { $0.foodID ?? $0.mealID ?? "-" })")
        }
    }

    func testCommonAmounts() {
        let bread = parse("two slices of bread").items.first
        XCTAssertEqual(bread?.foodID, "aa137a")
        XCTAssertEqual(bread?.qty, 2)
        XCTAssertEqual(bread?.unit, "slice")
        let gravy = parse("half a can of mushroom gravy").items.first
        XCTAssertEqual(gravy?.foodID, "4b86d2")
        XCTAssertEqual(gravy?.qty, 0.5)
        XCTAssertEqual(gravy?.unit, "can")
        let d = draft("one and a half scoops of peanut butter protein")
        XCTAssertEqual(d.lines.first?.food.id, "a21abf")
        XCTAssertEqual(d.lines.first?.qty, 1.5)
    }

    func testHabitsSeeTodaysBreakfast() {
        let habits = MealHabits(ledger: ledger, today: "2026-10-25")
        XCTAssertTrue(habits.eatenToday.contains("m-standard-breakfast"))
        XCTAssertFalse(habits.ranked(ledger.sortedMeals).isEmpty)
        let afternoon = Calendar.current.date(bySettingHour: 13, minute: 0, second: 0, of: Date())!
        let next = habits.nextUsual(ledger.sortedMeals, after: afternoon, excluding: ["m-potato-bowl"])
        XCTAssertNotEqual(next?.slot, .breakfast)
        XCTAssertNotEqual(next?.id, "m-standard-breakfast")
    }

    // MARK: numbers and intent

    func testNumberWords() {
        XCTAssertEqual(NumberWords.tokens("one and a half cups"), ["1.5", "cups"])
        XCTAssertEqual(NumberWords.tokens("a hundred and fifty grams"), ["150", "grams"])
        XCTAssertEqual(NumberWords.tokens("two hundred and fifty g"), ["250", "g"])
        XCTAssertEqual(NumberWords.tokens("three quarters of a cup"), ["0.75", "cup"])
        XCTAssertEqual(NumberWords.tokens("¾ cup"), ["0.75", "cup"])
        XCTAssertEqual(NumberWords.tokens("1/2 can"), ["0.5", "can"])
        XCTAssertEqual(NumberWords.tokens("half a can"), ["0.5", "can"])
        XCTAssertEqual(NumberWords.tokens("1 1/2 scoops"), ["1.5", "scoops"])
        XCTAssertEqual(NumberWords.tokens("150g tofu"), ["150", "g", "tofu"])
        XCTAssertEqual(NumberWords.tokens("a cup"), ["a", "cup"])
        XCTAssertEqual(NumberWords.tokens("twenty-five grams"), ["25", "grams"])
    }

    func testIntent() {
        XCTAssertEqual(LogIntent.of("What's for dinner"), .question)
        XCTAssertEqual(LogIntent.of("any ideas for lunch"), .question)
        XCTAssertEqual(LogIntent.of("potato bowl?"), .question)
        XCTAssertEqual(LogIntent.of("had the potato bowl"), .log)
        XCTAssertEqual(LogIntent.of("can of romano beans"), .log)
        XCTAssertEqual(LogIntent.of("planned dinner"), .log)
    }

    private func date(hour: Int) -> Date {
        Calendar.current.date(bySettingHour: hour, minute: 0, second: 0, of: Date())!
    }
}
