import SwiftUI

/// Correcting a log: swap a misheard food, change amounts, remove an item, move it to
/// another meal. Saving replaces the group; untouched items keep their snapshot.
struct LoggedEditView: View {
    var groupID: String

    @Environment(FoodStore.self) private var store
    @Environment(Router.self) private var router

    @State private var items: [Item] = []
    @State private var slot: MealSlot = .snack
    @State private var loaded = false
    @State private var swapping: Item.ID?
    @State private var adding = false
    @State private var gramsFor: Item.ID?
    @State private var gramsText = ""
    @State private var confirmDelete = false

    struct Item: Identifiable, Hashable {
        let id = UUID()
        var entry: Entry?
        var food: Food?
        var qty: Double
        var unit: String

        var changed: Bool {
            guard let entry else { return true }
            return food?.id != entry.foodID || qty != entry.qty || unit.lowercased() != entry.unit.lowercased()
        }
        var name: String { LogDraft.displayName(food?.name ?? entry?.label ?? "Entry") }
    }

    private var group: LogGroup? { store.ledger.group(id: groupID) }
    private var context: LogCoordinator.Context? { LogCoordinator.shared.context(for: groupID) }
    private var isReceipt: Bool { store.receipt?.groupID == groupID }

    var body: some View {
        Group {
            if let group {
                content(group)
            } else {
                VStack(spacing: 12) {
                    Cap("Edit log")
                    Text("This entry is no longer in the log.").font(Typo.body).foregroundStyle(Theme.amberText)
                    Button("Close") { router.sheet = nil }.buttonStyle(AmberCardButtonStyle(filled: true, fill: false))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .foregroundStyle(Theme.text)
        .presentationDetents([.large])
        .presentationBackground(Theme.deepAmber)
        .presentationCornerRadius(28)
        .onAppear(perform: load)
        .sheet(isPresented: swapBinding) {
            FoodPicker(title: adding ? "Add a food" : "Swap for", ledger: store.ledger) { food in pick(food) }
        }
        .alert("Grams", isPresented: gramsBinding) {
            TextField("Grams", text: $gramsText).keyboardType(.decimalPad)
            Button("Set") { setGrams() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("How many grams did you have?")
        }
        .confirmationDialog("Delete this log?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) { save(force: true) }
        } message: {
            Text(group.map { $0.entries.map { "\(LogDraft.displayName($0.label)) · \($0.amountText)" }.joined(separator: "\n") } ?? "")
        }
    }

    private func content(_ group: LogGroup) -> some View {
        let total = items.reduce(Macros.zero) { $0 + (macros(for: $1) ?? .zero) }
        return ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Cap("Logged · \(slot.title)", color: Theme.muted)
                    Spacer()
                    Cap("Editing", color: Theme.muted)
                }
                .padding(.top, 8)
                HStack(alignment: .firstTextBaseline) {
                    Text(group.label).font(.system(size: 22, weight: .semibold)).tracking(-0.44)
                    Spacer()
                    Text(Format.int(total.kcal)).font(Typo.mono(22)).contentTransition(.numericText())
                }
                if let context, context.source == .voice || context.reading != nil {
                    heard(context)
                }
                VStack(spacing: 4) {
                    ForEach($items) { $item in
                        row($item)
                        alternatives(for: item)
                    }
                }
                Button { adding = true } label: {
                    Label("Add a food", systemImage: "plus").font(.system(size: 14, weight: .semibold))
                }
                .foregroundStyle(Theme.amberText)
                .frame(minHeight: 44)

                slotPicker
                footer(total, group: group)
                HStack(spacing: 8) {
                    Button(isReceipt ? "Undo" : "Delete") {
                        if isReceipt {
                            LogCoordinator.shared.forget(groupID)
                            store.undoReceipt()
                            router.sheet = nil
                        } else {
                            confirmDelete = true
                        }
                    }
                    .buttonStyle(AmberCardButtonStyle(filled: false, height: 48))
                    Button("Done") { save(force: false) }
                        .buttonStyle(.primary)
                }
                .padding(.top, 4)
            }
            .padding(18)
        }
        .scrollIndicators(.hidden)
    }

    private func heard(_ context: LogCoordinator.Context) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Cap("Heard", color: Theme.amber)
            Text("“\(context.heard)”").font(.system(size: 15)).lineSpacing(2)
            if let reading = context.reading {
                Text(reading).font(.system(size: 13)).foregroundStyle(Theme.muted)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 12).padding(.horizontal, 14)
        .background(RoundedRectangle(cornerRadius: 14).fill(Theme.deepAmber2))
    }

    private func row(_ item: Binding<Item>) -> some View {
        let i = item.wrappedValue
        let step = Self.step(for: i.unit, qty: i.qty)
        return HStack(spacing: 8) {
            Menu {
                if i.food != nil || i.entry?.foodID != nil {
                    Button("Swap food", systemImage: "arrow.left.arrow.right") { swapping = i.id }
                }
                if let food = i.food, food.basis == .per100g || food.servingGrams != nil {
                    Button("Enter grams", systemImage: "scalemass") {
                        gramsText = i.unit == "g" ? Format.trim(i.qty) : ""
                        gramsFor = i.id
                    }
                }
                Button("Remove", systemImage: "minus.circle", role: .destructive) {
                    withAnimation(.snappy) { items.removeAll { $0.id == i.id } }
                }
            } label: {
                Text(i.name).font(.system(size: 14)).foregroundStyle(Theme.amberText)
                    .lineLimit(2).multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            }
            if i.food != nil {
                stepButton("minus", label: "Less \(i.name)") { item.wrappedValue.qty = max(step, Self.round(i.qty - step)) }
                Text(Format.amount(qty: i.qty, unit: i.unit))
                    .font(Typo.mono(14))
                    .foregroundStyle(i.changed && i.entry != nil ? Theme.amber : Theme.text)
                    .frame(width: 70)
                    .lineLimit(1).minimumScaleFactor(0.7)
                    .contentTransition(.numericText())
                stepButton("plus", label: "More \(i.name)") { item.wrappedValue.qty = Self.round(i.qty + step) }
            } else {
                Text("estimate").font(Typo.mono(12)).foregroundStyle(Theme.muted)
            }
            Text(Format.int(macros(for: i)?.kcal)).font(Typo.mono(14)).frame(width: 38, alignment: .trailing)
        }
        .animation(.snappy, value: i.qty)
    }

    private func stepButton(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 15, weight: .medium))
                .frame(width: 44, height: 44)
                .overlay(Circle().stroke(Theme.amberDivider))
                .contentShape(Circle())
        }
        .foregroundStyle(Theme.text)
        .accessibilityLabel(label)
    }

    @ViewBuilder private func alternatives(for item: Item) -> some View {
        let ledger = store.ledger
        if let fid = item.entry?.foodID, item.food?.id == fid, let alts = context?.alternatives[fid], !alts.isEmpty {
            HStack(spacing: 8) {
                ForEach(alts.compactMap { ledger.foods[$0] }) { alt in
                    Button("\(LogDraft.displayName(alt.name)) instead") { replace(item.id, with: alt) }
                        .buttonStyle(AmberCardButtonStyle(filled: false, height: 36, fill: false))
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.bottom, 6)
        }
    }

    private var slotPicker: some View {
        HStack(spacing: 6) {
            ForEach(MealSlot.allCases) { s in
                Button(s.title) { slot = s }
                    .font(.system(size: 14, weight: .semibold))
                    .frame(maxWidth: .infinity, minHeight: 40)
                    .background(Capsule().fill(slot == s ? Theme.deepAmber2 : .clear))
                    .overlay(Capsule().stroke(slot == s ? Theme.amber.opacity(0.6) : Theme.amberDivider))
                    .foregroundStyle(slot == s ? Theme.text : Theme.amberText)
                    .accessibilityAddTraits(slot == s ? .isSelected : [])
            }
        }
    }

    private func footer(_ total: Macros, group: LogGroup) -> some View {
        let ledger = store.ledger
        let day = group.entries.first?.eatenOn ?? Clock.dayString()
        let carbs = ledger.carbMode == "net" ? total.netCarbs : total.carbs
        // Today as it would be after saving: the edit's difference on top of what is logged.
        let delta = Macros(kcal: total.kcal - group.macros.kcal, protein: total.protein - group.macros.protein,
                           carbs: total.carbs - group.macros.carbs, fat: total.fat - group.macros.fat,
                           fiber: total.fiber - group.macros.fiber)
        let left = ledger.macroStatus(on: day, extra: delta).first?.left
        let bank = ledger.bank ?? 0
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("P \(Format.int(total.protein)) · C \(Format.int(carbs)) · F \(Format.int(total.fat))").foregroundStyle(Theme.muted)
                Spacer()
                if let left {
                    Text(left >= 0 ? "\(Format.int(left)) left" : "\(Format.int(-left)) over")
                        .foregroundStyle(left >= 0 ? Theme.text : Theme.coral)
                }
            }
            .font(Typo.mono(13))
            if let left, left < 0, bank > 0 {
                Text("The bank has \(Text(Format.trim(bank)).font(Typo.mono(14))) if you want it.")
                    .font(.system(size: 14)).foregroundStyle(Theme.amberText)
            }
        }
        .padding(.top, 12)
        .overlay(alignment: .top) { Hairline(color: Theme.amberDivider) }
    }

    // MARK: logic

    private func load() {
        guard !loaded, let group else { return }
        loaded = true
        slot = group.meal ?? MealSlot.guess()
        items = group.entries.map { e in
            Item(entry: e, food: e.foodID.flatMap { store.ledger.foods[$0] }, qty: e.qty, unit: e.unit)
        }
    }

    private func macros(for item: Item) -> Macros? {
        if let entry = item.entry, !item.changed { return entry.macros }
        guard let food = item.food else { return item.entry?.macros }
        return store.ledger.preview(food, qty: item.qty, unit: item.unit)
    }

    private func pick(_ food: Food) {
        if adding {
            let amount = GroupEdits.amount(keeping: 1, food.servingLabel ?? "serving", for: food)
            items.append(Item(food: food, qty: amount.qty, unit: amount.unit))
        } else if let id = swapping {
            replace(id, with: food)
        }
        swapping = nil
        adding = false
    }

    private func replace(_ id: Item.ID, with food: Food) {
        guard let i = items.firstIndex(where: { $0.id == id }) else { return }
        let amount = GroupEdits.amount(keeping: items[i].qty, items[i].unit, for: food)
        items[i].food = food
        items[i].qty = amount.qty
        items[i].unit = amount.unit
    }

    private func setGrams() {
        guard let id = gramsFor, let i = items.firstIndex(where: { $0.id == id }),
              let g = Double(gramsText.replacingOccurrences(of: ",", with: ".")), g > 0 else { return }
        items[i].qty = g
        items[i].unit = "g"
        gramsFor = nil
    }

    private func save(force: Bool) {
        guard let group else { router.sheet = nil; return }
        if items.isEmpty && !force {
            confirmDelete = true
            return
        }
        let ledger = store.ledger
        let unchanged = items.count == group.entries.count && items.allSatisfy { !$0.changed } && slot == group.meal
        if unchanged { router.sheet = nil; return }
        let label = items.count > 1 || group.entries.first?.groupLabel != nil ? group.label : nil
        let events: [Event] = items.compactMap { item in
            if let entry = item.entry, !item.changed {
                return GroupEdits.copy(entry, ledger: ledger, meal: slot, groupID: group.id, groupLabel: label)
            }
            guard let food = item.food else { return nil }
            let original = group.entries.first
            return try? Commands.log(food, qty: item.qty, unit: item.unit, day: original?.eatenOn ?? Clock.dayString(),
                                     meal: slot, source: item.entry?.source ?? original?.source ?? "text",
                                     groupID: group.id, groupLabel: label,
                                     at: Clock.parseISO(original?.eatenAt) ?? Date())
        }
        if events.isEmpty, isReceipt { store.dismissReceipt() }
        store.replace(group: group, with: events)
        router.sheet = nil
    }

    static func step(for unit: String, qty: Double) -> Double {
        let u = unit.lowercased()
        if Ledger.gramUnits.contains(u) { return qty >= 200 ? 25 : qty >= 50 ? 10 : 5 }
        if ["cup", "scoop", "serving", "can", "tbsp", "tsp", "block", "pack", "bag", "1/5 package"].contains(u) { return 0.25 }
        return qty < 1 ? 0.5 : 1
    }

    static func round(_ x: Double) -> Double { (x * 100).rounded() / 100 }

    private var swapBinding: Binding<Bool> {
        Binding(get: { swapping != nil || adding }, set: { if !$0 { swapping = nil; adding = false } })
    }

    private var gramsBinding: Binding<Bool> {
        Binding(get: { gramsFor != nil }, set: { if !$0 { gramsFor = nil } })
    }
}

/// Search the library and pick one food.
struct FoodPicker: View {
    var title: String
    var ledger: Ledger
    var onPick: (Food) -> Void
    @State private var query = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(title).font(.system(size: 17, weight: .semibold))
                Spacer()
                Button("Cancel") { dismiss() }.foregroundStyle(Theme.text2)
            }
            .padding(.horizontal, 20).frame(height: 56)
            TextField("", text: $query, prompt: Text("Search foods").foregroundStyle(Theme.muted))
                .font(.system(size: 16))
                .padding(.horizontal, 16).frame(height: 44)
                .background(Capsule().fill(Theme.bar))
                .padding(.horizontal, 16)
                .autocorrectionDisabled()
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(results) { food in
                        Button {
                            onPick(food)
                            dismiss()
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(food.name).font(Typo.row).lineLimit(1)
                                    Text("\(Format.int(food.kcal)) kcal per \(food.perLabel)").font(.system(size: 13)).foregroundStyle(Theme.text3)
                                }
                                Spacer()
                            }
                            .frame(minHeight: 56)
                            .overlay(alignment: .bottom) { Hairline() }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 20)
            }
        }
        .foregroundStyle(Theme.text)
        .presentationBackground(Theme.surface)
        .presentationDetents([.large])
    }

    private var results: [Food] {
        let direct = ledger.searchFoods(query)
        guard !query.isEmpty, direct.isEmpty else { return direct }
        // Nothing contains the words: fall back to the sound-alike matcher.
        let items = LocalLogInterpreter().parse(query, ledger: ledger).items.compactMap(\.foodID)
        return items.compactMap { ledger.foods[$0] }
    }
}
