import SwiftUI

/// A usual meal: its components with default amounts. Logging it writes one entry per
/// component so each ingredient's numbers stay honest. `mealID` nil starts a new one.
struct MealDetailView: View {
    var mealID: String?
    @Environment(FoodStore.self) private var store
    @Environment(Router.self) private var router
    @Environment(\.dismiss) private var dismiss

    @State private var draft: UsualMeal?
    @State private var aliasText = ""
    @State private var editing = false
    @State private var picking = false
    @State private var confirmDelete = false
    @State private var logError: String?

    private var stored: UsualMeal? { mealID.flatMap { store.ledger.meals[$0] } }
    private var isNew: Bool { stored == nil }

    var body: some View {
        Group {
            if mealID != nil && stored == nil && draft == nil {
                VStack(spacing: 0) {
                    ScreenHeader("")
                    Text("This meal was deleted.").font(Typo.body).foregroundStyle(Theme.text2).padding(20)
                    Spacer()
                }
            } else if editing, draft != nil {
                editor
            } else if let meal = stored {
                detail(meal)
            } else {
                Color.clear
            }
        }
        .page()
        .onAppear(perform: start)
        .sheet(isPresented: $picking) {
            LibFoodPicker { food in
                let a = Ledger.libBasisAmount(food)
                draft?.components.append(.init(foodID: food.id, qty: a.qty, unit: a.unit))
            }
        }
    }

    private func start() {
        guard draft == nil else { return }
        if let meal = stored {
            draft = meal
        } else {
            draft = UsualMeal(id: "", name: "", aliases: [], slot: MealSlot.guess(), components: [], note: nil)
            editing = true
        }
        aliasText = (draft?.aliases ?? []).joined(separator: ", ")
    }

    // MARK: detail

    private func detail(_ meal: UsualMeal) -> some View {
        let ledger = store.ledger
        let m = ledger.preview(meal)
        return VStack(spacing: 0) {
            ScreenHeader("", trailing: AnyView(Cap(meal.slot.map { "Usual \($0.rawValue)" } ?? "Usual meal").padding(.trailing, 10)))
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text(meal.name).font(.system(size: 32, weight: .semibold)).tracking(-0.96)
                        .padding(.top, 4).padding(.bottom, 4)
                    if !meal.aliases.isEmpty { aliasLine(meal.aliases) }

                    LibNumeral(kcal: m.kcal) {
                        HStack(spacing: 0) {
                            Text("kcal · ")
                            Text("\(Format.int(m.protein)) g P").foregroundStyle(Theme.amber)
                            Text(" · defaults")
                        }
                    }

                    ForEach(Array(meal.components.enumerated()), id: \.offset) { _, c in
                        componentRow(c, ledger: ledger)
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Cap("From what you've said")
                            Spacer()
                            Button("All notes") { router.push(.memory) }
                                .font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.text2)
                                .frame(minHeight: 44)
                        }
                        if let note = meal.note, !note.isEmpty {
                            Text(note).font(Typo.body).lineSpacing(3)
                        } else {
                            Text("Nothing noted about this meal yet.").font(Typo.body).foregroundStyle(Theme.text3)
                        }
                    }
                    .padding(.top, 20)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                VStack(spacing: 8) {
                    if let logError { Text(logError).font(.system(size: 13)).foregroundStyle(Theme.coral) }
                    HStack(spacing: 8) {
                        Button("Change amounts") {
                            draft = meal
                            aliasText = meal.aliases.joined(separator: ", ")
                            editing = true
                        }
                        .buttonStyle(OutlineButtonStyle(height: 52, fill: true))
                        Button("Log with defaults") { log(meal) }
                            .buttonStyle(.primary)
                            .disabled(meal.components.isEmpty)
                    }
                }
                .padding(.horizontal, 20).padding(.top, 10).padding(.bottom, 12)
                .background(Theme.graphite)
            }
        }
    }

    private func aliasLine(_ aliases: [String]) -> some View {
        var text = AttributedString("Also answers to ")
        for (i, a) in aliases.enumerated() {
            if i > 0 { text += AttributedString(i == aliases.count - 1 ? " and " : ", ") }
            var alias = AttributedString(a)
            alias.font = Typo.mono(14)
            text += alias
        }
        return Text(text).font(.system(size: 14)).foregroundStyle(Theme.text2)
    }

    private func componentRow(_ c: UsualMeal.Component, ledger: Ledger) -> some View {
        let food = ledger.foods[c.foodID]
        let m = food.flatMap { ledger.preview($0, qty: c.qty, unit: c.unit) }
        return Button {
            if food != nil { router.push(.food(c.foodID)) }
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(food?.name ?? "Deleted food").font(.system(size: 15, weight: .medium))
                        .foregroundStyle(food == nil ? Theme.text3 : Theme.text)
                    if let m {
                        Text("\(Format.int(m.protein)) g P · \(Format.int(m.netCarbs)) C · \(Format.int(m.fat)) F")
                            .font(Typo.mono(12)).foregroundStyle(Theme.text3)
                    } else {
                        Text("Skipped when logged").font(Typo.mono(12)).foregroundStyle(Theme.text3)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Text(Format.amount(qty: c.qty, unit: c.unit)).font(Typo.mono(14))
                Text(m.map { Format.int($0.kcal) } ?? "–").font(Typo.mono(14)).frame(minWidth: 34, alignment: .trailing)
            }
            .frame(minHeight: 62)
            .overlay(alignment: .bottom) { Hairline() }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func log(_ meal: UsualMeal) {
        do {
            let events = try Commands.log(meal, in: store.ledger)
            guard !events.isEmpty else { return }
            store.log(events)
            router.show(.today)
        } catch {
            logError = error.localizedDescription
        }
    }

    // MARK: editor

    private var draftBinding: Binding<UsualMeal> {
        Binding(get: { draft ?? UsualMeal(id: "", name: "", aliases: [], slot: nil, components: [], note: nil) },
                set: { draft = $0 })
    }

    private var canSave: Bool {
        guard let d = draft else { return false }
        return !d.name.trimmingCharacters(in: .whitespaces).isEmpty && !d.components.isEmpty
    }

    private var editor: some View {
        let ledger = store.ledger
        let meal = draftBinding
        let m = ledger.preview(meal.wrappedValue)
        return VStack(spacing: 0) {
            HStack {
                Button("Cancel") {
                    if isNew { dismiss() } else { draft = stored; editing = false }
                }
                .foregroundStyle(Theme.text2).frame(minHeight: 44)
                Spacer()
                Text(isNew ? "New meal" : "Change amounts").font(.system(size: 17, weight: .semibold))
                Spacer()
                Button("Save", action: save)
                    .fontWeight(.semibold)
                    .foregroundStyle(canSave ? Theme.text : Theme.text3)
                    .disabled(!canSave)
                    .frame(minHeight: 44)
            }
            .padding(.horizontal, 20)
            .frame(height: 56)

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    TextField("", text: meal.name, prompt: Text("Meal name").foregroundStyle(Theme.text3))
                        .font(.system(size: 28, weight: .semibold))
                        .padding(.vertical, 6)
                        .overlay(alignment: .bottom) { Hairline() }
                    LibTextField(label: "Also answers to", text: $aliasText, prompt: "comma separated")

                    LibNumeral(kcal: m.kcal) {
                        HStack(spacing: 0) {
                            Text("kcal · ")
                            Text("\(Format.int(m.protein)) g P").foregroundStyle(Theme.amber)
                        }
                    }

                    ForEach(Array(meal.wrappedValue.components.enumerated()), id: \.offset) { i, c in
                        editableComponent(i, c, ledger: ledger)
                    }

                    Button { picking = true } label: { Label("Add a component", systemImage: "plus") }
                        .buttonStyle(LibPillStyle())
                        .padding(.top, 12)

                    Cap("Usually eaten at").padding(.top, 24).padding(.bottom, 8)
                    Picker("Slot", selection: meal.slot) {
                        Text("Any").tag(MealSlot?.none)
                        ForEach(MealSlot.allCases) { Text($0.title).tag(MealSlot?.some($0)) }
                    }
                    .pickerStyle(.segmented)

                    Cap("Note").padding(.top, 24).padding(.bottom, 8)
                    TextField("", text: Binding(get: { meal.wrappedValue.note ?? "" },
                                                set: { meal.wrappedValue.note = $0.isEmpty ? nil : $0 }),
                              prompt: Text("When you have it, what to swap").foregroundStyle(Theme.text3), axis: .vertical)
                        .font(Typo.body)
                        .lineLimit(2...6)
                        .padding(12)
                        .background(RoundedRectangle(cornerRadius: 12).fill(Theme.surface))

                    if let logError { Text(logError).font(.system(size: 13)).foregroundStyle(Theme.coral).padding(.top, 12) }

                    HStack(spacing: 8) {
                        Button("Log it") { log(normalized()) }
                            .buttonStyle(OutlineButtonStyle(height: 52, fill: true))
                            .disabled(meal.wrappedValue.components.isEmpty)
                        if !isNew {
                            Button("Delete meal") { confirmDelete = true }
                                .buttonStyle(OutlineButtonStyle(border: Theme.coral, height: 52, fill: true))
                        }
                    }
                    .padding(.top, 28)
                    Text("Log it uses these amounts once without saving them.")
                        .font(.system(size: 12)).foregroundStyle(Theme.text3).padding(.top, 8)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 32)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .confirmationDialog("Delete \(stored?.name ?? "this meal")?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                if let id = stored?.id { store.append(Commands.deleteMeal(id)) }
                dismiss()
            }
        } message: {
            Text("The foods stay in the library and past logs keep their numbers.")
        }
    }

    private func editableComponent(_ i: Int, _ c: UsualMeal.Component, ledger: Ledger) -> some View {
        let food = ledger.foods[c.foodID]
        let m = food.flatMap { ledger.preview($0, qty: c.qty, unit: c.unit) }
        let grams = Ledger.gramUnits.contains(c.unit)
        let qty = Binding<Double>(get: { draft?.components.libAt(i)?.qty ?? 0 },
                                  set: { if draft?.components.indices.contains(i) == true { draft?.components[i].qty = $0 } })
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(food?.name ?? "Deleted food").font(.system(size: 15, weight: .medium)).lineLimit(1)
                Spacer()
                Text(m.map { "\(Format.int($0.kcal)) kcal" } ?? "–").font(Typo.mono(13)).foregroundStyle(Theme.text2)
                Button {
                    draft?.components.remove(at: i)
                } label: {
                    Image(systemName: "minus.circle").font(.system(size: 18)).foregroundStyle(Theme.text2).frame(width: 44, height: 44)
                }
                .accessibilityLabel("Remove \(food?.name ?? "component")")
            }
            HStack {
                AmountStepper(qty: qty, unit: c.unit, step: grams ? 10 : 0.25)
                Spacer()
                if let food, Ledger.libCanWeigh(food), let su = Ledger.libServingUnit(food) {
                    Button(grams ? "Servings" : "Grams") { switchUnit(i, food: food, servingUnit: su) }
                        .font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.text2).frame(minHeight: 44)
                }
            }
        }
        .padding(.vertical, 10)
        .overlay(alignment: .bottom) { Hairline() }
    }

    private func switchUnit(_ i: Int, food: Food, servingUnit: String) {
        guard var c = draft?.components.libAt(i) else { return }
        if Ledger.gramUnits.contains(c.unit) {
            let sg = food.servingGrams ?? 100
            c.qty = max(0.25, ((c.qty / sg) * 4).rounded() / 4)
            c.unit = servingUnit
        } else {
            let g = (try? Ledger.resolveAmount(food, qty: c.qty, unit: c.unit))?.grams ?? 100
            c.qty = max(10, (g / 5).rounded() * 5)
            c.unit = "g"
        }
        draft?.components[i] = c
    }

    /// The draft with its aliases parsed, the name trimmed and an id assigned.
    private func normalized() -> UsualMeal {
        var m = draft ?? UsualMeal(id: "", name: "", aliases: [], slot: nil, components: [], note: nil)
        m.name = m.name.trimmingCharacters(in: .whitespaces)
        m.aliases = aliasText.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        m.components = m.components.filter { $0.qty > 0 }
        if m.id.isEmpty {
            let slug = m.name.lowercased().map { $0.isLetter || $0.isNumber ? String($0) : "-" }.joined()
                .split(separator: "-").joined(separator: "-")
            let id = "m-\(slug.isEmpty ? EventID.make() : slug)"
            m.id = store.ledger.meals[id] == nil ? id : "\(id)-\(EventID.make())"
        }
        return m
    }

    private func save() {
        let m = normalized()
        store.append(Commands.setMeal(m))
        draft = m
        if isNew || mealID != m.id {
            // A new meal has no route of its own yet; go back to the library, where it now shows.
            dismiss()
        } else {
            editing = false
        }
    }
}

/// Search the library and pick a food, for adding a meal component.
struct LibFoodPicker: View {
    var onPick: (Food) -> Void
    @Environment(FoodStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    var body: some View {
        let foods = store.ledger.libFoodsByUse(query)
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Add a component").font(.system(size: 17, weight: .semibold))
                Spacer()
                Button("Done") { dismiss() }.foregroundStyle(Theme.text2).frame(minHeight: 44)
            }
            LibSearchField(text: $query, prompt: "Search \(store.ledger.foods.count) foods")
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(foods) { food in
                        Button {
                            onPick(food)
                            dismiss()
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(food.name).font(Typo.row).lineLimit(1)
                                    Text(store.ledger.libBasisLine(food)).font(Typo.mono(12)).foregroundStyle(Theme.text3)
                                }
                                Spacer()
                                Image(systemName: "plus").foregroundStyle(Theme.text2)
                            }
                            .frame(minHeight: 56)
                            .overlay(alignment: .bottom) { Hairline() }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    if foods.isEmpty {
                        Text("No food matches. Add it from the Foods tab first.")
                            .font(Typo.body).foregroundStyle(Theme.text3).padding(.top, 12)
                    }
                }
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .foregroundStyle(Theme.text)
        .presentationBackground(Theme.surface)
        .presentationDragIndicator(.visible)
    }
}

extension Array {
    func libAt(_ i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}
