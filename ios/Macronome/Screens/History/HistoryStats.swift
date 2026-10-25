import Foundation

/// A run of days shown together on History: a trailing week or a calendar month.
struct HistWindow: Equatable {
    enum Range: String, CaseIterable, Identifiable {
        case week, month
        var id: String { rawValue }
        var title: String { rawValue.capitalized }
    }

    /// Oldest first.
    var days: [String]
    var title: String

    /// Seven days ending on `today`, moved back `offset` weeks: "18 to 24 Oct".
    static func week(today: String, offset: Int) -> HistWindow {
        let end = Clock.addDays(today, -7 * offset)
        let days = (0..<7).map { Clock.addDays(end, $0 - 6) }
        return HistWindow(days: days, title: rangeTitle(days.first!, days.last!))
    }

    /// The calendar month containing `today`, moved back `offset` months: "October 2026".
    static func month(today: String, offset: Int) -> HistWindow {
        let cal = Calendar.current
        guard let t = Clock.date(fromDay: today),
              let shifted = cal.date(byAdding: .month, value: -offset, to: t),
              let interval = cal.dateInterval(of: .month, for: shifted) else { return week(today: today, offset: 0) }
        let first = Clock.dayString(interval.start)
        let count = cal.range(of: .day, in: .month, for: shifted)?.count ?? 30
        let days = (0..<count).map { Clock.addDays(first, $0) }
        let f = DateFormatter()
        f.dateFormat = "MMMM yyyy"
        return HistWindow(days: days, title: f.string(from: interval.start))
    }

    static func window(_ range: Range, today: String, offset: Int) -> HistWindow {
        range == .week ? week(today: today, offset: offset) : month(today: today, offset: offset)
    }

    static func rangeTitle(_ a: String, _ b: String) -> String {
        guard let da = Clock.date(fromDay: a), let db = Clock.date(fromDay: b) else { return "\(a) to \(b)" }
        let sameMonth = Calendar.current.isDate(da, equalTo: db, toGranularity: .month)
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_GB")
        f.dateFormat = sameMonth ? "d" : "d MMM"
        let g = DateFormatter()
        g.locale = Locale(identifier: "en_GB")
        g.dateFormat = "d MMM"
        return "\(f.string(from: da)) to \(g.string(from: db))"
    }

    /// "13 Sep".
    static func shortDay(_ day: String) -> String {
        guard let d = Clock.date(fromDay: day) else { return day }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_GB")
        f.dateFormat = "d MMM"
        return f.string(from: d)
    }
}

/// Averages over the finished days in a window (today is still open, so it is left out).
struct HistStats: Equatable {
    var fullDays: [String]
    var avgKcal: Double?
    var avgProtein: Double?
    var avgFat: Double?
}

extension Ledger {
    /// kcal over (+) or under (−) the day's own target, override included. nil when
    /// nothing was logged or there is no target.
    func histDiff(on day: String) -> Double? {
        guard let target = targets(on: day).kcal else { return nil }
        let t = totals(on: day)
        guard t.count > 0 else { return nil }
        return t.macros.kcal - target
    }

    func histStats(_ days: [String], today: String) -> HistStats {
        let full = days.filter { $0 < today && totals(on: $0).count > 0 }
        guard !full.isEmpty else { return HistStats(fullDays: []) }
        let sums = full.reduce(Macros.zero) { $0 + totals(on: $1).macros }
        let n = Double(full.count)
        return HistStats(fullDays: full, avgKcal: sums.kcal / n, avgProtein: sums.protein / n, avgFat: sums.fat / n)
    }

    /// Finished days in a window as bank moves, newest first: under the target saves
    /// the difference, over spends it.
    func histBankMoves(_ days: [String], today: String) -> [(day: String, change: Double)] {
        days.filter { $0 < today }.reversed().compactMap { d in histDiff(on: d).map { (d, -$0) } }
    }
}
