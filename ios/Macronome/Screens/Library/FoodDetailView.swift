import SwiftUI

/// One food: its numbers for an amount, what it is part of, and how often it is eaten.
struct FoodDetailView: View {
    var foodID: String
    @Environment(FoodStore.self) private var store
    @Environment(Router.self) private var router
    @Environment(\.dismiss) private var dismiss

    @State private var qty: Double?
    @State private var unit = ""
    @State private var editing = false
    @State private var draft = FoodDraft()
    @State private var confirmDelete = false
    @State private var logError: String?

    var body: some View {
        Group {
            if let food = store.ledger.foods[foodID] {
                if editing { editor(food) } else { detail(food) }
            } else {
                VStack(spacing: 0) {
                    ScreenHeader("")
                    Text("This food was deleted. Entries logged with it keep their numbers.")
                        .font(Typo.body).foregroundStyle(Theme.text2).padding(20)
                    Spacer()
                }
            }
        }
        .page()
        .onAppear(perform: setDefaultAmount)
    }

    // MARK: detail

    private func detail(_ food: Food) -> some View {
        let ledger = store.ledger
        let uses = ledger.entries.filter { $0.foodID == food.id }
        let amount = (qty: qty ?? Ledger.libBasisAmount(food).qty, unit: unit.isEmpty ? Ledger.libBasisAmount(food).unit : unit)
        let m = ledger.preview(food, qty: amount.qty, unit: amount.unit) ?? .zero
        let partOf = ledger.libMeals(using: food.id)

        return VStack(spacing: 0) {
            ScreenHeader("", trailing: AnyView(
                Cap(uses.isEmpty ? "Not logged yet" : uses.count == 1 ? "Logged once" : "Logged \(uses.count) times")
                    .padding(.trailing, 10)))
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text(food.name)
                        .font(.system(size: 30, weight: .semibold)).tracking(-0.9)
                        .padding(.top, 4).padding(.bottom, 16)

                    amountPicker(food)

                    LibNumeral(kcal: m.kcal) {
                        Text("kcal for \(Format.amount(qty: amount.qty, unit: amount.unit))")
                    }

                    macroTable(m, food: food, factor: factor(food, amount))

                    if !food.micros.isEmpty { microsSection(food, factor: factor(food, amount)) }

                    if !partOf.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Cap("Part of")
                            LibFlow(spacing: 8) {
                                ForEach(partOf) { meal in
                                    Button(meal.name) { router.push(.meal(meal.id)) }
                                        .buttonStyle(LibPillStyle(filled: true))
                                }
                            }
                        }
                        .padding(.top, 20)
                    }

                    if !food.aliases.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Cap("Also answers to")
                            LibFlow { ForEach(food.aliases, id: \.self) { LibTag(text: $0) } }
                        }
                        .padding(.top, 18)
                    }

                    aboutSection(food, uses: uses)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                VStack(spacing: 8) {
                    if let logError {
                        Text(logError).font(.system(size: 13)).foregroundStyle(Theme.coral)
                    }
                    HStack(spacing: 8) {
                        Button("Edit numbers") {
                            draft = FoodDraft(food)
                            editing = true
                        }
                        .buttonStyle(OutlineButtonStyle(height: 52, fill: true))
                        .frame(maxWidth: .infinity)
                        Button("Log \(Format.amount(qty: amount.qty, unit: amount.unit))") { log(food, amount) }
                            .buttonStyle(.primary)
                            .frame(maxWidth: .infinity)
                            .disabled(amount.qty <= 0)
                    }
                }
                .padding(.horizontal, 20).padding(.top, 10).padding(.bottom, 12)
                .background(Theme.graphite)
            }
        }
    }

    /// Radio presets (the stated serving, ¾ of it, 100 g) and a stepper for anything else.
    private func amountPicker(_ food: Food) -> some View {
        let presets = presets(food)
        let current = (qty: qty ?? 0, unit: unit)
        return VStack(alignment: .leading, spacing: 12) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Array(presets.enumerated()), id: \.offset) { _, p in
                        Button(p.title) {
                            qty = p.qty
                            unit = p.unit
                        }
                        .buttonStyle(LibPillStyle(selected: p.qty == current.qty && p.unit == current.unit))
                        .accessibilityAddTraits(p.qty == current.qty && p.unit == current.unit ? .isSelected : [])
                    }
                }
            }
            .scrollClipDisabled()
            HStack {
                AmountStepper(qty: Binding(get: { qty ?? 1 }, set: { qty = $0 }), unit: unit,
                              step: Ledger.gramUnits.contains(unit) ? 10 : 0.25)
                Spacer()
                if Ledger.libCanWeigh(food), let su = Ledger.libServingUnit(food) {
                    Button(Ledger.gramUnits.contains(unit) ? "Use \(su == "serving" ? "servings" : su)" : "Use grams") {
                        toggleUnit(food, servingUnit: su)
                    }
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.text2)
                    .frame(minHeight: 44)
                }
            }
        }
    }

    private func macroTable(_ m: Macros, food: Food, factor: Double) -> some View {
        VStack(spacing: 0) {
            macroRow("Protein", grams: m.protein, color: Theme.amber)
            macroRow("Carbs", grams: m.carbs)
            if food.fiber != nil || food.fiberSoluble != nil {
                macroRow("Fiber", grams: m.fiber, indent: true)
                if let s = food.fiberSoluble, let i = food.fiberInsoluble {
                    macroRow("Soluble · insoluble", text: "\(Format.trim(s * factor)) · \(Format.trim(i * factor)) g", indent: true, height: 36)
                } else if let s = food.fiberSoluble {
                    macroRow("Soluble", grams: s * factor, indent: true, height: 36)
                } else if let i = food.fiberInsoluble {
                    macroRow("Insoluble", grams: i * factor, indent: true, height: 36)
                }
                macroRow("Net carbs", grams: m.netCarbs, indent: true)
            }
            macroRow("Fat", grams: m.fat)
        }
        .font(Typo.mono(14))
    }

    private func macroRow(_ label: String, grams: Double? = nil, text: String? = nil, color: Color = Theme.text,
                          indent: Bool = false, height: CGFloat = 44) -> some View {
        HStack {
            Text(label).foregroundStyle(indent ? Theme.text2 : color)
            Spacer()
            Text(text ?? "\(Format.trim(grams ?? 0)) g").foregroundStyle(indent ? Theme.text2 : Theme.text)
        }
        .padding(.leading, indent ? 14 : 0)
        .frame(height: height)
        .overlay(alignment: .bottom) { Hairline() }
        .accessibilityElement(children: .combine)
    }

    private func microsSection(_ food: Food, factor: Double) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Cap("Also on the label").padding(.top, 22).padding(.bottom, 6)
            ForEach(LibMicro.sorted(food.micros), id: \.key) { item in
                let l = LibMicro.label(item.key)
                HStack {
                    Text(l.name).foregroundStyle(Theme.text2)
                    Spacer()
                    Text("\(LibMicro.value(item.value * factor)) \(l.unit)")
                }
                .font(Typo.mono(13))
                .frame(height: 36)
                .overlay(alignment: .bottom) { Hairline() }
            }
        }
    }

    private func aboutSection(_ food: Food, uses: [Entry]) -> some View {
        let last = uses.map(\.eatenOn).max()
        var lines: [(String, String)] = []
        lines.append(("Stated per", food.basis == .per100g ? "100 g" : [food.servingLabel ?? "serving", food.servingGrams.map { "\(Format.trim($0)) g" }].compactMap { $0 }.joined(separator: " · ")))
        if let source = food.source { lines.append(("Source", sourceName(source))) }
        if let last { lines.append(("Last logged", Format.dayHeader(last))) }
        if let created = food.createdAt, let d = Clock.parseISO(created) {
            lines.append(("Added", Format.dayHeader(Clock.dayString(d))))
        }
        return VStack(alignment: .leading, spacing: 0) {
            Cap("About").padding(.top, 22).padding(.bottom, 6)
            ForEach(lines.indices, id: \.self) { i in
                let line = lines[i]
                HStack {
                    Text(line.0).foregroundStyle(Theme.text2)
                    Spacer()
                    Text(line.1)
                }
                .font(.system(size: 14))
                .frame(minHeight: 40)
                .overlay(alignment: .bottom) { Hairline() }
            }
            if let notes = food.notes, !notes.isEmpty {
                Text(notes).font(Typo.body).foregroundStyle(Theme.text2).padding(.top, 12)
            }
        }
    }

    private func sourceName(_ s: String) -> String {
        switch s {
        case "label_photo": "Label photo"
        case "usda": "USDA reference"
        case "estimate": "Estimate"
        case "manual": "Entered by hand"
        default: s.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    // MARK: amounts

    private struct Preset { var title: String; var qty: Double; var unit: String }

    private func presets(_ food: Food) -> [Preset] {
        var out: [Preset] = []
        if let su = Ledger.libServingUnit(food) {
            let grams = food.servingGrams.map { " · \(Format.trim($0)) g" } ?? ""
            out.append(Preset(title: Format.amount(qty: 1, unit: su) + grams, qty: 1, unit: su))
            out.append(Preset(title: Format.amount(qty: 0.75, unit: su), qty: 0.75, unit: su))
            out.append(Preset(title: Format.amount(qty: 2, unit: su), qty: 2, unit: su))
        }
        if Ledger.libCanWeigh(food) {
            out.append(Preset(title: "100 g", qty: 100, unit: "g"))
            if Ledger.libServingUnit(food) == nil {
                out.append(Preset(title: "150 g", qty: 150, unit: "g"))
                out.append(Preset(title: "200 g", qty: 200, unit: "g"))
            }
        }
        return out
    }

    private func setDefaultAmount() {
        guard qty == nil, let food = store.ledger.foods[foodID] else { return }
        let a = Ledger.libBasisAmount(food)
        qty = a.qty
        unit = a.unit
    }

    private func toggleUnit(_ food: Food, servingUnit: String) {
        let current = qty ?? 1
        if Ledger.gramUnits.contains(unit) {
            let sg = food.servingGrams ?? 100
            qty = max(0.25, ((current / sg) * 4).rounded() / 4)
            unit = servingUnit
        } else {
            let grams = (try? Ledger.resolveAmount(food, qty: current, unit: unit))?.grams ?? 100
            qty = max(10, (grams / 5).rounded() * 5)
            unit = "g"
        }
    }

    private func factor(_ food: Food, _ amount: (qty: Double, unit: String)) -> Double {
        (try? Ledger.resolveAmount(food, qty: amount.qty, unit: amount.unit))?.factor ?? 0
    }

    private func log(_ food: Food, _ amount: (qty: Double, unit: String)) {
        do {
            let ev = try Commands.log(food, qty: amount.qty, unit: amount.unit, meal: MealSlot.guess())
            store.log([ev])
            router.show(.today)
        } catch {
            logError = error.localizedDescription
        }
    }

    // MARK: editor

    private func editor(_ food: Food) -> some View {
        let changes = changedFields(food)
        return VStack(spacing: 0) {
            HStack {
                Button("Cancel") { editing = false }.foregroundStyle(Theme.text2).frame(minHeight: 44)
                Spacer()
                Text("Edit numbers").font(.system(size: 17, weight: .semibold))
                Spacer()
                Button("Save") {
                    if !changes.isEmpty { store.append(Commands.updateFood(food.id, fields: changes)) }
                    editing = false
                }
                .fontWeight(.semibold)
                .foregroundStyle(draft.isComplete ? Theme.text : Theme.text3)
                .disabled(!draft.isComplete)
                .frame(minHeight: 44)
            }
            .padding(.horizontal, 20)
            .frame(height: 56)

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Logged entries keep the numbers they were logged with. Changes apply to what you log from now on.")
                        .font(.system(size: 13)).foregroundStyle(Theme.text3)
                        .padding(.bottom, 12)

                    LibTextField(label: "Name", text: $draft.name)
                    LibTextField(label: "Also answers to", text: $draft.aliases, prompt: "comma separated")

                    Cap("Numbers are per").padding(.top, 22).padding(.bottom, 8)
                    Picker("Basis", selection: $draft.basis) {
                        Text("Serving").tag(Basis.serving)
                        Text("100 g").tag(Basis.per100g)
                    }
                    .pickerStyle(.segmented)
                    .padding(.bottom, 4)
                    LibTextField(label: "Serving called", text: Binding(get: { draft.servingLabel ?? "" },
                                                                         set: { draft.servingLabel = $0.isEmpty ? nil : $0 }),
                                 prompt: "cup, scoop, serving")
                    NumberField(label: "Serving weight", value: $draft.servingGrams, unit: "g")

                    Cap("Macros").padding(.top, 22).padding(.bottom, 4)
                    NumberField(label: "Calories", value: $draft.kcal, unit: "kcal")
                    NumberField(label: "Protein", value: $draft.protein, unit: "g")
                    NumberField(label: "Carbs", value: $draft.carbs, unit: "g")
                    NumberField(label: "Fiber", value: $draft.fiber, unit: "g")
                    NumberField(label: "  Soluble", value: $draft.fiberSoluble, unit: "g")
                    NumberField(label: "  Insoluble", value: $draft.fiberInsoluble, unit: "g")
                    NumberField(label: "Fat", value: $draft.fat, unit: "g")
                    if let warning = draft.labelArithmeticWarning {
                        Text(warning).font(.system(size: 13)).foregroundStyle(Theme.text2).padding(.top, 8)
                    }

                    if !draft.micros.isEmpty {
                        Cap("Also on the label").padding(.top, 22).padding(.bottom, 4)
                        ForEach(LibMicro.sorted(draft.micros), id: \.key) { item in
                            let l = LibMicro.label(item.key)
                            NumberField(label: l.name, value: Binding(get: { draft.micros[item.key] },
                                                                      set: { draft.micros[item.key] = $0 }),
                                        unit: l.unit)
                        }
                    }

                    Cap("Notes").padding(.top, 22).padding(.bottom, 8)
                    TextField("", text: Binding(get: { draft.notes ?? "" }, set: { draft.notes = $0.isEmpty ? nil : $0 }),
                              prompt: Text("Anything worth remembering").foregroundStyle(Theme.text3), axis: .vertical)
                        .font(Typo.body)
                        .lineLimit(2...6)
                        .padding(12)
                        .background(RoundedRectangle(cornerRadius: 12).fill(Theme.surface))

                    Button("Delete food", role: .destructive) { confirmDelete = true }
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.coral)
                        .frame(minHeight: 44)
                        .padding(.top, 28)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 32)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .confirmationDialog("Delete \(food.name)?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                store.append(Commands.deleteFood(food.id))
                editing = false
                dismiss()
            }
        } message: {
            Text(deleteMessage(food))
        }
    }

    private func deleteMessage(_ food: Food) -> String {
        var text = "It leaves the library. Entries already logged keep their numbers."
        let meals = store.ledger.libMeals(using: food.id).map(\.name)
        if !meals.isEmpty {
            text += " \(meals.joined(separator: ", ")) will log without it."
        }
        return text
    }

    /// Only the fields that differ from the stored food, for one food_update event.
    private func changedFields(_ food: Food) -> [String: JSONValue] {
        var edited = draft.food(id: food.id)
        if food.source == nil && edited.source == "manual" { edited.source = nil }
        let before = Ledger.foodFields(food)
        let after = Ledger.foodFields(edited)
        var out: [String: JSONValue] = [:]
        for (k, v) in after where before[k] != v { out[k] = v }
        return out
    }
}
