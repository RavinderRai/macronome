import Foundation

/// What the widgets show for one day, computed from the same ledger as the app.
struct DaySnapshot: Hashable, Sendable {
    var day: String
    var kcalLeft: Double
    var kcalEaten: Double
    var kcalTarget: Double
    var protein: MacroStatus
    var carbs: MacroStatus
    var fat: MacroStatus
    /// Calories eaten from protein, carbs and fat, for the ring.
    var split: (protein: Double, carbs: Double, fat: Double)

    static func == (a: DaySnapshot, b: DaySnapshot) -> Bool {
        a.day == b.day && a.kcalEaten == b.kcalEaten && a.kcalTarget == b.kcalTarget
    }
    func hash(into h: inout Hasher) { h.combine(day); h.combine(kcalEaten) }

    init(ledger: Ledger, day: String = Clock.dayString()) {
        self.day = day
        let rows = ledger.macroStatus(on: day)
        let kcal = rows[0]
        kcalTarget = kcal.target ?? 0
        kcalEaten = kcal.eaten
        kcalLeft = (kcal.target ?? 0) - kcal.eaten
        protein = rows[1]
        carbs = rows[2]
        fat = rows[3]
        split = ledger.totals(on: day).macros.kcalSplit
    }

    /// The design's sample day, for widget previews and placeholders.
    static let sample: DaySnapshot = {
        var s = DaySnapshot(ledger: Ledger())
        s.kcalTarget = 1700; s.kcalEaten = 941; s.kcalLeft = 759
        s.protein = MacroStatus(key: .protein, label: "Protein", eaten: 92, target: 165, isFloor: false)
        s.carbs = MacroStatus(key: .carbs, label: "Net carbs", eaten: 70, target: 156, isFloor: false)
        s.fat = MacroStatus(key: .fat, label: "Fat", eaten: 32, target: 45, isFloor: false)
        s.split = (357, 305, 279)
        return s
    }()
}
