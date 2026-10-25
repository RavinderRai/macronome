import Foundation

/// When each usual meal tends to be eaten, read back from the log. Drives the order of
/// the meal chips and the "what the evening bowl would do" line on the card.
struct MealHabits: Sendable {
    /// Meal id -> minutes after midnight of every past time it was eaten.
    private(set) var times: [String: [Int]] = [:]
    /// Meal id -> the most times it was eaten in one day.
    private(set) var maxPerDay: [String: Int] = [:]
    private(set) var eatenToday: Set<String> = []
    private(set) var slotsToday: Set<MealSlot> = []
    private(set) var historyDays = 0

    init() {}

    init(ledger: Ledger, today: String) {
        let meals = ledger.sortedMeals
        historyDays = ledger.loggedDays.filter { $0 < today }.count
        for day in ledger.loggedDays {
            var counts: [String: Int] = [:]
            for group in ledger.groups(on: day) {
                if day == today, let s = group.meal { slotsToday.insert(s) }
                guard let meal = Self.meal(for: group, in: meals) else { continue }
                if day == today {
                    eatenToday.insert(meal.id)
                    continue
                }
                counts[meal.id, default: 0] += 1
                if let d = Clock.parseISO(group.eatenAt) {
                    let c = Calendar.current.dateComponents([.hour, .minute], from: d)
                    times[meal.id, default: []].append((c.hour ?? 0) * 60 + (c.minute ?? 0))
                }
            }
            for (id, n) in counts { maxPerDay[id] = max(maxPerDay[id] ?? 0, n) }
        }
    }

    /// The usual meal a logged group was, if any. Snack and evening bowls share their
    /// foods, so a tie goes to the one whose amounts are closest.
    static func meal(for group: LogGroup, in meals: [UsualMeal]) -> UsualMeal? {
        if let named = meals.first(where: { $0.name.caseInsensitiveCompare(group.label) == .orderedSame }),
           group.entries.first?.groupLabel != nil {
            return named
        }
        let ids = Set(group.entries.compactMap(\.foodID))
        let fits = meals.filter { m in
            let overlap = m.components.filter { ids.contains($0.foodID) }.count
            return overlap >= max(2, m.components.count - 1) || (m.components.count == 1 && overlap == 1 && ids.count == 1)
        }
        guard !fits.isEmpty else { return nil }
        func distance(_ m: UsualMeal) -> Double {
            m.components.reduce(0) { sum, c in
                guard let e = group.entries.first(where: { $0.foodID == c.foodID }) else { return sum + 1 }
                return sum + abs(e.qty - c.qty) / max(c.qty, 0.01)
            }
        }
        return fits.min { distance($0) < distance($1) }
    }

    private func minutes(_ date: Date) -> Int {
        let c = Calendar.current.dateComponents([.hour, .minute], from: date)
        return (c.hour ?? 0) * 60 + (c.minute ?? 0)
    }

    /// How strongly this meal belongs to the next few hours. Past occurrences fade fast,
    /// upcoming ones slowly, so after lunch the snack and evening bowls lead.
    func score(_ meal: UsualMeal, at date: Date) -> Double {
        let now = minutes(date)
        let days = Double(max(historyDays, 1))
        var s = (times[meal.id] ?? []).reduce(0.0) { sum, t in
            let d = Double(t - now)
            let sigma = d >= 0 ? 240.0 : 60.0
            return sum + exp(-(d * d) / (2 * sigma * sigma))
        } / days
        if let slot = meal.slot, slot == MealSlot.guess(at: date) { s += 0.02 }
        if eatenToday.contains(meal.id), (maxPerDay[meal.id] ?? 1) <= 1 { s *= 0.1 }
        else if let slot = meal.slot, slot != .snack, slotsToday.contains(slot) { s *= 0.3 }
        return s
    }

    func ranked(_ meals: [UsualMeal], at date: Date = Date()) -> [UsualMeal] {
        meals.map { ($0, score($0, at: date), times[$0.id]?.count ?? 0) }
            .sorted { ($0.1, $0.2, $1.0.name) > ($1.1, $1.2, $0.0.name) }
            .map(\.0)
    }

    /// The usual meal most likely still to come today, when it is a real habit.
    func nextUsual(_ meals: [UsualMeal], after date: Date = Date(), excluding: Set<String> = []) -> UsualMeal? {
        let now = minutes(date)
        let days = Double(max(historyDays, 1))
        let current = Ledger.slotOrder(MealSlot.guess(at: date))
        let candidates = meals.filter { m in
            guard !excluding.contains(m.id), !eatenToday.contains(m.id) else { return false }
            guard let slot = m.slot else { return true }
            // Never a breakfast in the afternoon, nor a meal for a slot already eaten.
            if slot != .snack, Ledger.slotOrder(slot) < current { return false }
            if slot != .snack, slotsToday.contains(slot) { return false }
            return true
        }
        let scored = candidates.map { m -> (UsualMeal, Double) in
            let later = (times[m.id] ?? []).filter { $0 > now + 30 }
            return (m, Double(later.count) / days)
        }
        guard let best = scored.max(by: { $0.1 < $1.1 }), best.1 >= 0.3 else { return nil }
        return best.0
    }
}
