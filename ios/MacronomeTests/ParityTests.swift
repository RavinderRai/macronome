import XCTest

/// The Swift ledger must score every day exactly like food-log/fl.py. The fixture is
/// `fl.py range --json` over the whole log; regenerate it after the log changes.
final class ParityTests: XCTestCase {
    private var repo: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    }

    func testDailyTotalsMatchFoodLog() throws {
        let events = EventCodec.decodeLines(try Data(contentsOf: repo.appendingPathComponent("food-log/events.jsonl")))
        let ledger = Ledger(events: events)
        let fixture = try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: repo.appendingPathComponent("ios/MacronomeTests/fl-range.json")))
        XCTAssertFalse(fixture.days.isEmpty)
        for day in fixture.days {
            let t = ledger.totals(on: day.day)
            XCTAssertEqual(t.count, day.n, "entry count on \(day.day)")
            XCTAssertEqual(t.macros.kcal, day.kcal, accuracy: 0.05, "kcal on \(day.day)")
            XCTAssertEqual(t.macros.protein, day.protein, accuracy: 0.05, "protein on \(day.day)")
            XCTAssertEqual(t.macros.carbs, day.carbs, accuracy: 0.05, "carbs on \(day.day)")
            XCTAssertEqual(t.macros.fat, day.fat, accuracy: 0.05, "fat on \(day.day)")
        }
    }

    func testFindFoodResolvesAliasesLikeFoodLog() throws {
        let events = EventCodec.decodeLines(try Data(contentsOf: repo.appendingPathComponent("food-log/events.jsonl")))
        let ledger = Ledger(events: events)
        guard case .found(let potato) = ledger.findFood("potato") else { return XCTFail("potato") }
        XCTAssertEqual(potato.name, "russet potato")
        guard case .found(let gusta) = ledger.findFood("gusta") else { return XCTFail("gusta") }
        XCTAssertEqual(gusta.id, "bf697f")
        if case .found = ledger.findFood("beyond yourself") { XCTFail("two protein flavours should be ambiguous") }
    }

    func testPluralServingLabelsResolve() throws {
        let events = EventCodec.decodeLines(try Data(contentsOf: repo.appendingPathComponent("food-log/events.jsonl")))
        let ledger = Ledger(events: events)
        guard case .found(let patty) = ledger.findFood("beyond burger") else { return XCTFail() }
        XCTAssertEqual(try Ledger.resolveAmount(patty, qty: 2, unit: "patties").factor, 2)
        guard case .found(let meatball) = ledger.findFood("meatballs") else { return XCTFail() }
        XCTAssertEqual(try Ledger.resolveAmount(meatball, qty: 3, unit: "meatballs").factor, 3)
    }

    private struct Fixture: Decodable {
        struct Day: Decodable { var day: String; var n: Int; var kcal: Double; var protein: Double; var carbs: Double; var fat: Double }
        var days: [Day]
    }
}
