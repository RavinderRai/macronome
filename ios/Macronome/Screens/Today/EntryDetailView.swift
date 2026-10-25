import SwiftUI

/// One logged row in full: kcal and macros, each component, micronutrients from the
/// labels, how fiber was counted, and where it came from.
struct EntryDetailView: View {
    var groupID: String

    @Environment(FoodStore.self) private var store
    @Environment(Router.self) private var router
    @Environment(\.dismiss) private var dismiss
    @State private var confirmDelete = false

    var body: some View {
        let ledger = store.ledger
        Group {
            if let group = ledger.group(id: groupID) {
                content(group, ledger: ledger)
            } else {
                VStack(spacing: 0) {
                    ScreenHeader("Entry")
                    Spacer()
                    Text("This entry was deleted.").font(Typo.body).foregroundStyle(Theme.text3)
                    Spacer()
                }
            }
        }
        .page()
    }

    private func content(_ group: LogGroup, ledger: Ledger) -> some View {
        let m = group.macros
        let day = group.entries.first?.eatenOn ?? Clock.dayString()
        return VStack(spacing: 0) {
            HStack {
                Button { dismiss() } label: {
                    Image(systemName: "chevron.left").font(.system(size: 18, weight: .medium)).frame(width: 44, height: 44)
                }
                .accessibilityLabel("Back")
                Spacer()
                Cap("\(group.meal?.title ?? "Entry") · \(Self.dayLabel(day))").padding(.trailing, 10)
            }
            .padding(.horizontal, 10)
            .frame(height: 56)

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .lastTextBaseline) {
                        Text(group.label).font(.system(size: 32, weight: .semibold)).tracking(-0.96).lineLimit(2)
                        Spacer(minLength: 12)
                        HStack(alignment: .lastTextBaseline, spacing: 0) {
                            Text(Format.int(m.kcal)).numeralStyle(52)
                            Text(" kcal").font(Typo.mono(13)).foregroundStyle(Theme.text2)
                        }
                    }
                    .padding(.top, 4).padding(.bottom, 18)
                    .overlay(alignment: .bottom) { Hairline(color: Theme.text) }

                    macroGrid(m, ledger: ledger)

                    if let fiber = fiberNote(group, ledger: ledger) {
                        Text(fiber).font(.system(size: 13)).foregroundStyle(Theme.text3).lineSpacing(2)
                            .padding(.bottom, 12)
                    }

                    Cap("What was in it").padding(.vertical, 8)
                    VStack(spacing: 0) {
                        ForEach(group.entries) { e in component(e) }
                    }
                    .overlay(alignment: .top) { Hairline() }

                    let micros = Micros.sorted(group.entries.reduce(into: [String: Double]()) { sum, e in
                        for (k, v) in e.micros { sum[k, default: 0] += v }
                    })
                    if !micros.isEmpty {
                        Cap("From the labels").padding(.top, 20).padding(.bottom, 8)
                        LazyVGrid(columns: [GridItem(.flexible(), spacing: 20), GridItem(.flexible())], spacing: 0) {
                            ForEach(micros, id: \.key) { item in
                                let (name, unit) = Micros.split(item.key)
                                HStack {
                                    Text(name).foregroundStyle(Theme.text2).lineLimit(1).minimumScaleFactor(0.8)
                                    Spacer(minLength: 6)
                                    Text(Micros.value(item.value, unit: unit))
                                }
                                .font(Typo.mono(13))
                                .frame(height: 34)
                                .overlay(alignment: .bottom) { Hairline() }
                            }
                        }
                    }

                    provenance(group).padding(.top, 20)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }
            .scrollIndicators(.hidden)

            actions(group, ledger: ledger)
                .padding(.horizontal, 20)
                .padding(.bottom, 8)
        }
        .confirmationDialog("Delete \(group.label)?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button(group.entries.count > 1 ? "Delete \(group.entries.count) entries" : "Delete entry", role: .destructive) {
                if store.receipt?.groupID == group.id { store.dismissReceipt() }
                store.append(group.entries.map { Commands.deleteEntry($0.id) })
                dismiss()
            }
        } message: {
            Text(group.entries.map { "\(LogDraft.displayName($0.label)) · \($0.amountText) · \(Format.int($0.kcal)) kcal" }
                .joined(separator: "\n"))
        }
    }

    private func macroGrid(_ m: Macros, ledger: Ledger) -> some View {
        let net = ledger.carbMode == "net"
        let cells: [(String, Double, Color)] = [
            ("Protein", m.protein, Theme.amber), (net ? "Net carbs" : "Carbs", net ? m.netCarbs : m.carbs, Theme.text3),
            ("Fat", m.fat, Theme.text3), ("Fiber", m.fiber, Theme.text3),
        ]
        return HStack(alignment: .top, spacing: 12) {
            ForEach(cells, id: \.0) { cell in
                VStack(alignment: .leading, spacing: 4) {
                    Cap(cell.0, color: cell.2)
                    Text("\(Format.trim(cell.1, digits: cell.1 < 10 ? 1 : 0)) g").font(Typo.mono(17))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .combine)
            }
        }
        .padding(.vertical, 16)
    }

    private func component(_ e: Entry) -> some View {
        let row = HStack(spacing: 10) {
            Text(LogDraft.displayName(e.label)).font(.system(size: 15)).lineLimit(1)
            Spacer(minLength: 8)
            Text(e.amountText).font(Typo.mono(13)).foregroundStyle(Theme.text3)
            Text(Format.int(e.kcal)).font(Typo.mono(14)).frame(width: 40, alignment: .trailing)
        }
        .frame(minHeight: 50)
        .overlay(alignment: .bottom) { Hairline() }
        .contentShape(Rectangle())
        return Group {
            if let fid = e.foodID, store.ledger.foods[fid] != nil {
                Button { router.push(.food(fid)) } label: { row }.buttonStyle(.plain)
            } else {
                row
            }
        }
    }

    /// "Counted at 669 rather than the labels' 689: 10 g of fiber at 2 kcal/g (auto)."
    private func fiberNote(_ group: LogGroup, ledger: Ledger) -> String? {
        let adjust = group.entries.reduce(0) { $0 + $1.kcalAdjust }
        guard adjust > 0 else { return nil }
        let label = group.entries.reduce(0) { $0 + $1.kcalLabel }
        let fiber = group.macros.fiber
        let perGram = fiber > 0 ? " (\(Format.trim(adjust / fiber)) kcal per gram)" : ""
        return "Counted as \(Format.int(group.macros.kcal)) rather than the labels' \(Format.int(label)): " +
            "\(Format.int(adjust)) kcal off for \(Format.trim(fiber)) g of fiber\(perGram), under the \(ledger.fiberMode) fiber setting."
    }

    private func provenance(_ group: LogGroup) -> some View {
        let first = group.entries.first
        let source = first?.source.map(Self.sourceText) ?? "Logged"
        let time = Format.time(first?.eatenAt)
        let confidence = first?.confidence.map { "\($0) confidence" }
        let note = group.entries.compactMap(\.note).first
        return VStack(alignment: .leading, spacing: 6) {
            Cap("Logged")
            Text([source, time, confidence].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "))
                .font(.system(size: 14)).foregroundStyle(Theme.text2)
            if let note { Text(note).font(.system(size: 14)).foregroundStyle(Theme.text3) }
        }
    }

    private func actions(_ group: LogGroup, ledger: Ledger) -> some View {
        VStack(spacing: 4) {
            HStack(spacing: 8) {
                Button("Change amount") { router.sheet = .editGroup(group.id) }
                    .buttonStyle(OutlineButtonStyle(fill: true))
                // Tap moves to the obvious other meal; hold for every slot.
                Menu {
                    ForEach(MealSlot.allCases.filter { $0 != group.meal }) { slot in
                        Button(slot.title) { move(group, to: slot, ledger: ledger) }
                    }
                } label: {
                    Text(Self.obviousMove(group.meal).map { "Move to \($0.rawValue)" } ?? "Move to…")
                        .font(.system(size: 15, weight: .semibold))
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .overlay(Capsule().stroke(Theme.text, lineWidth: 1))
                        .contentShape(Capsule())
                } primaryAction: {
                    if let slot = Self.obviousMove(group.meal) { move(group, to: slot, ledger: ledger) }
                }
                .foregroundStyle(Theme.text)
            }
            HStack {
                Button("Log again") {
                    store.log(GroupEdits.logAgain(group, ledger: ledger))
                    router.popToRoot()
                }
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.text)
                .frame(minHeight: 44)
                Spacer()
                Button("Delete entry") { confirmDelete = true }
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.amber)
                    .frame(minHeight: 44)
            }
        }
    }

    /// Lunch and dinner are the usual mix-up; snacks and breakfast get the full menu.
    static func obviousMove(_ slot: MealSlot?) -> MealSlot? {
        switch slot {
        case .lunch: .dinner
        case .dinner: .lunch
        default: nil
        }
    }

    private func move(_ group: LogGroup, to slot: MealSlot, ledger: Ledger) {
        store.replace(group: group, with: GroupEdits.move(group, to: slot, ledger: ledger))
    }

    static func sourceText(_ s: String) -> String {
        switch s {
        case "voice": "Said out loud"
        case "text": "Typed"
        case "label_photo", "label": "From a label photo"
        case "photo": "From a plate photo"
        case "estimate": "Estimate"
        case "plan": "From the plan"
        case "widget": "From the widget"
        case "siri": "From Siri"
        default: s.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    static func dayLabel(_ day: String) -> String {
        let today = Clock.dayString()
        if day == today { return "Today" }
        if day == Clock.addDays(today, -1) { return "Yesterday" }
        return Format.dayHeader(day)
    }
}
