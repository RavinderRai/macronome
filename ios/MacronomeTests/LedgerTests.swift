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
}
