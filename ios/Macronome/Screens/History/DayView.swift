import SwiftUI

/// A past day, read back in Today's vocabulary: the numeral, the strip, macro columns
/// and the log grouped by meal.
struct DayView: View {
    var day: String
    @Environment(FoodStore.self) private var store
    @Environment(Router.self) private var router

    var body: some View {
        let ledger = store.ledger
        let status = ledger.macroStatus(on: day)
        let kcal = status.first { $0.key == .kcal }
        let fiber = status.first { $0.key == .fiber }
        let target = kcal?.target ?? 0
        let eaten = kcal?.eaten ?? 0
        let groups = ledger.groups(on: day)
        let note = ledger.dayNotes[day].flatMap { $0.isEmpty ? nil : $0 }

        VStack(spacing: 0) {
            ScreenHeader("", trailing: AnyView(Cap(day == store.today ? "Today" : "History").padding(.trailing, 10)))
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    CaloriesHeader(day: day, dayNumber: ledger.dayNumber(day), bank: nil,
                                   left: target - eaten, eaten: eaten, target: max(target, 1),
                                   afterPlan: nil, segments: ledger.stripSegments(on: day, includePlans: false))
                    MacroColumns(rows: status)

                    if ledger.hasOverride(on: day) || note != nil || fiber != nil {
                        VStack(alignment: .leading, spacing: 0) {
                            if let fiber {
                                line("Fiber", fiber.target.map { "\(Format.int(fiber.eaten)) g · floor \(Format.int($0))" }
                                     ?? "\(Format.int(fiber.eaten)) g")
                            }
                            if ledger.hasOverride(on: day) { line("Target this day", overrideText(ledger)) }
                            if let note {
                                VStack(alignment: .leading, spacing: 6) {
                                    Cap("Note")
                                    Text(note).font(Typo.body).foregroundStyle(Theme.text2)
                                }
                                .padding(.vertical, 12)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .overlay(alignment: .bottom) { Hairline() }
                            }
                        }
                        .overlay(alignment: .top) { Hairline() }
                    }

                    if groups.isEmpty {
                        Text("Nothing logged this day.").font(Typo.body).foregroundStyle(Theme.text3)
                    } else {
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(sections(groups), id: \.title) { section in
                                SectionHeader(title: section.title,
                                              trailing: Format.int(section.groups.reduce(0) { $0 + $1.macros.kcal }))
                                    .padding(.top, section.title == sections(groups).first?.title ? 0 : 18)
                                ForEach(section.groups) { g in
                                    Button { router.push(.entry(g.id)) } label: { EntryRow(group: g) }
                                        .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 32)
            }
        }
        .page()
    }

    private struct Section { var title: String; var groups: [LogGroup] }

    private func sections(_ groups: [LogGroup]) -> [Section] {
        var out: [Section] = []
        for g in groups.sorted(by: { Ledger.slotOrder($0.meal) < Ledger.slotOrder($1.meal) }) {
            let title = g.meal?.title ?? "Other"
            if let i = out.firstIndex(where: { $0.title == title }) { out[i].groups.append(g) } else {
                out.append(Section(title: title, groups: [g]))
            }
        }
        return out
    }

    private func overrideText(_ ledger: Ledger) -> String {
        let t = ledger.targets(on: day), s = ledger.standingTargets
        var parts: [String] = []
        if t.kcal != s.kcal { parts.append("\(Format.int(t.kcal)) kcal") }
        if t.protein != s.protein { parts.append("\(Format.int(t.protein)) P") }
        if t.carbs != s.carbs { parts.append("\(Format.int(t.carbs)) C") }
        if t.fat != s.fat { parts.append("\(Format.int(t.fat)) F") }
        return parts.isEmpty ? "Same as usual" : parts.joined(separator: " · ")
    }

    private func line(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(.system(size: 15)).foregroundStyle(Theme.text2)
            Spacer()
            Text(value).font(Typo.mono(13))
        }
        .frame(minHeight: 44)
        .overlay(alignment: .bottom) { Hairline() }
    }
}
