import XCTest

@MainActor
final class FoodStoreTests: XCTestCase {
    func testAppendsToAnExistingLog() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("store-\(UUID().uuidString).jsonl")
        // A log without a trailing newline, as a hand edit or git merge can leave it.
        try Data(#"{"id":"a1","ts":"2026-10-01T08:00:00-04:00","type":"profile_set","key":"target_kcal","value":"1700"}"#.utf8).write(to: url)
        let store = FoodStore(fileURL: url)
        store.append(Commands.setProfile("diet", "vegan"))
        store.append(Commands.note("second write"))
        XCTAssertEqual(store.ledger.events.count, 3)
        XCTAssertEqual(store.ledger.profile["diet"], "vegan")
        let lines = try String(contentsOf: url, encoding: .utf8).split(separator: "\n")
        XCTAssertEqual(lines.count, 3)
    }
}
