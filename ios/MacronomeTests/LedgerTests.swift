import XCTest

final class LedgerTests: XCTestCase {
    func testFiberAutoSkipsLabelsThatAlreadyDiscount() {
        // Farm Girl crisps: 150 kcal, P13 C21 F2, fiber 5. 4*13+4*21+9*2 = 154, so
        // 150 >= 154 - 5 and auto deducts 10.
        XCTAssertEqual(Ledger.fiberAdjustment(fiber: 5, soluble: 5, insoluble: 0, mode: "auto",
                                              kcal: 150, protein: 13, carbs: 21, fat: 2), 10)
        XCTAssertEqual(Ledger.fiberAdjustment(fiber: 5, soluble: nil, insoluble: nil, mode: "auto",
                                              kcal: 140, protein: 13, carbs: 21, fat: 2), 0)
    }

    func testGroupIsRenamedAfterAnEntryIsRemoved() throws {
        let potato = Food(id: "p", name: "russet potato", aliases: [], basis: .per100g, servingGrams: nil, servingLabel: nil,
                          kcal: 79, protein: 2, carbs: 18, fat: 0, fiber: nil, fiberSoluble: nil, fiberInsoluble: nil,
                          micros: [:], source: nil, notes: nil, createdAt: nil)
        let cereal = Food(id: "c", name: "cinnamon crisps", aliases: [], basis: .per100g, servingGrams: nil, servingLabel: nil,
                          kcal: 400, protein: 8, carbs: 80, fat: 5, fiber: nil, fiberSoluble: nil, fiberInsoluble: nil,
                          micros: [:], source: nil, notes: nil, createdAt: nil)
        let a = try Commands.log(potato, qty: 300, unit: "g", day: "2026-11-01", groupID: "g1", groupLabel: "Potato + Cereal")
        let b = try Commands.log(cereal, qty: 40, unit: "g", day: "2026-11-01", groupID: "g1", groupLabel: "Potato + Cereal")
        let l = Ledger(events: [Commands.addFood(potato), Commands.addFood(cereal), a, b, Commands.deleteEntry(b.id)])
        XCTAssertEqual(l.groups(on: "2026-11-01").map(\.label), ["Russet potato"])
    }
}
