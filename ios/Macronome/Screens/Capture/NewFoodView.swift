import SwiftUI

/// NewFood.dc.html: the food as read off the label, editable, then saved to the
/// library and optionally logged.
struct NewFoodView: View {
    @Environment(FoodStore.self) private var store
    @Environment(Router.self) private var router
    @Environment(\.dismiss) private var dismiss

    @State private var draft: FoodDraft
    @State private var qty: Double
    @State private var saveError: String?

    init(draft: FoodDraft) {
        _draft = State(initialValue: draft)
        _qty = State(initialValue: draft.basis == .per100g ? (draft.servingGrams ?? 100) : 1)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Cap(draft.source == "label_photo" ? "New food · from the label" : "New food")
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark").font(.system(size: 18)).frame(width: 44, height: 44)
                }
                .accessibilityLabel("Close")
                .padding(.trailing, -10)
            }
            .frame(height: 48)
            .padding(.horizontal, 20)

            ScrollView {
                FoodDraftEditor(draft: $draft, ledger: store.ledger) { food in router.push(.food(food.id)) }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 24)
            }
            .scrollDismissesKeyboard(.interactively)

            bottomBar
        }
        .background(
            UnevenRoundedRectangle(topLeadingRadius: 22, topTrailingRadius: 22)
                .fill(Theme.surface)
                .ignoresSafeArea(edges: .bottom)
        )
        .padding(.top, 8)
        .background(CaptureColors.ground.ignoresSafeArea())
        .foregroundStyle(Theme.text)
        .toolbar(.hidden, for: .navigationBar)
    }

    private var logUnit: String { draft.basis == .per100g ? "g" : (draft.servingLabel ?? "serving") }

    private var bottomBar: some View {
        VStack(spacing: 10) {
            if let saveError {
                Text(saveError).font(.system(size: 13)).foregroundStyle(Theme.coral)
            }
            HStack(spacing: 8) {
                Text("Log now").font(.system(size: 15, weight: .medium))
                Spacer()
                AmountStepper(qty: $qty, unit: logUnit, step: draft.basis == .per100g ? 10 : 0.25, minimum: 0)
            }
            HStack(spacing: 8) {
                Button("Save only") { save(log: false) }
                    .buttonStyle(OutlineButtonStyle(height: 52, fill: true))
                Button("Save and log") { save(log: true) }
                    .buttonStyle(.primary)
                    .frame(minHeight: 52)
                    .disabled(qty <= 0)
            }
            .disabled(!draft.isComplete)
            .opacity(draft.isComplete ? 1 : 0.5)
        }
        .padding(EdgeInsets(top: 12, leading: 20, bottom: 20, trailing: 20))
        .background(Theme.surface)
        .overlay(alignment: .top) { Hairline() }
    }

    private func save(log: Bool) {
        let food = draft.food()
        var events = [Commands.addFood(food)]
        if log {
            do {
                events.append(try Commands.log(food, qty: qty, unit: logUnit, meal: MealSlot.guess(), source: InputSource.label.rawValue))
            } catch {
                saveError = error.localizedDescription
                return
            }
            // One append so the food exists before the entry replays.
            store.append(events[0])
            store.log([events[1]])
        } else {
            store.append(events)
        }
        router.show(.today)
    }
}

/// The editable food: name, aliases, basis and serving, macros, everything else on the
/// label, source. Shared by NewFood and the pantry review.
struct FoodDraftEditor: View {
    @Binding var draft: FoodDraft
    var ledger: Ledger
    /// Open a food already in the library with the same name.
    var onOpenExisting: ((Food) -> Void)?

    @State private var newAlias = ""
    @State private var keptPrinted = false
    @State private var splitFiber = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            nameField
            if let existing = duplicate { duplicateNote(existing) }
            servingSection
            macroSection
            fiberNote
            if let warning = draft.labelArithmeticWarning, !keptPrinted { arithmeticCard(warning) }
            aliasSection
            microsSection
            sourceSection
            if let raw = draft.rawText, !raw.isEmpty { rawSection(raw) }
        }
    }

    // MARK: name

    private var nameField: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Cap("Name")
                if draft.unsure("name") { Cap("Check", color: Theme.amber) }
            }
            .padding(.top, 4)
            TextField("", text: $draft.name, prompt: Text("What is it called?").foregroundStyle(Theme.text3), axis: .vertical)
                .font(.system(size: 22, weight: .semibold)).tracking(-0.4)
                .textInputAutocapitalization(.sentences)
                .frame(minHeight: 48)
                .overlay(alignment: .bottom) { Hairline(color: Theme.text) }
        }
    }

    /// A food already saved under this name or alias.
    private var duplicate: Food? {
        let n = Ledger.norm(draft.name)
        guard !n.isEmpty else { return nil }
        return ledger.sortedFoods.first { Ledger.norm($0.name) == n || $0.aliases.map(Ledger.norm).contains(n) }
    }

    private func duplicateNote(_ food: Food) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("You already have \(food.name), \(Format.int(food.kcal)) per \(food.perLabel).")
                .font(.system(size: 14)).foregroundStyle(Theme.planned)
            Spacer(minLength: 0)
            if let onOpenExisting {
                Button("Open it") { onOpenExisting(food) }
                    .buttonStyle(OutlineButtonStyle(height: 36))
            }
        }
        .padding(.top, 10)
    }

    // MARK: serving

    private var servingSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                basisChip("Per serving", .serving)
                basisChip("Per 100 g", .per100g)
            }
            .padding(.top, 16)
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Cap("Serving")
                        if draft.unsure("servingLabel") { Cap("Check", color: Theme.amber) }
                    }
                    TextField("", text: servingLabel, prompt: Text("cup, scoop, slice").foregroundStyle(Theme.text3))
                        .font(.system(size: 16)).textInputAutocapitalization(.never).autocorrectionDisabled()
                        .frame(height: 36)
                }
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Cap("Weighs")
                        if draft.unsure("servingGrams") { Cap("Check", color: Theme.amber) }
                    }
                    HStack(spacing: 4) {
                        TextField("–", value: $draft.servingGrams, format: .number.precision(.fractionLength(0...2)))
                            .keyboardType(.decimalPad).font(Typo.mono(16)).frame(height: 36)
                        Text("g").font(Typo.mono(13)).foregroundStyle(Theme.text3)
                    }
                }
                .frame(width: 110)
            }
            .overlay(alignment: .bottom) { Hairline() }
        }
    }

    private func basisChip(_ title: String, _ basis: Basis) -> some View {
        let on = draft.basis == basis
        return Button {
            draft.basis = basis
            if basis == .serving && (draft.servingLabel ?? "").isEmpty { draft.servingLabel = "serving" }
        } label: {
            Text(title)
                .font(.system(size: 14, weight: on ? .semibold : .medium))
                .padding(.horizontal, 16).frame(height: 36)
                .background(Capsule().fill(on ? Theme.text : .clear))
                .overlay(Capsule().stroke(on ? .clear : CaptureColors.stepperBorder, lineWidth: 1))
                .foregroundStyle(on ? Theme.graphite : Theme.text)
                .frame(minHeight: 44)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private var servingLabel: Binding<String> {
        Binding(get: { draft.servingLabel ?? "" }, set: { draft.servingLabel = $0.isEmpty ? nil : $0.lowercased() })
    }

    // MARK: macros

    private var perText: String {
        if draft.basis == .per100g { return "Per 100 g" }
        return "Per 1 \(draft.servingLabel ?? "serving")"
    }

    private var macroSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Cap(perText)
                Spacer()
                Cap(draft.source == "label_photo" ? "As printed" : "")
            }
            .padding(.top, 18).padding(.bottom, 10)
            VStack(spacing: 0) {
                LabelFieldRow(label: "Calories", value: field(\.kcal, "kcal"), unit: "", uncertain: draft.unsure("kcal"))
                LabelFieldRow(label: "Protein", value: field(\.protein, "protein"), unit: "g", labelColor: Theme.amber, uncertain: draft.unsure("protein"))
                LabelFieldRow(label: "Carbs", value: field(\.carbs, "carbs"), unit: "g", uncertain: draft.unsure("carbs"))
                LabelFieldRow(label: "of which fiber", value: field(\.fiber, "fiber"), unit: "g", indent: 14, labelColor: Theme.text2, uncertain: draft.unsure("fiber"))
                if showsSplit {
                    LabelFieldRow(label: "soluble", value: field(\.fiberSoluble, "fiberSoluble"), unit: "g", indent: 28, labelColor: Theme.text3, uncertain: draft.unsure("fiberSoluble"))
                    LabelFieldRow(label: "insoluble", value: field(\.fiberInsoluble, "fiberInsoluble"), unit: "g", indent: 28, labelColor: Theme.text3, uncertain: draft.unsure("fiberInsoluble"))
                }
                LabelFieldRow(label: "Fat", value: field(\.fat, "fat"), unit: "g", uncertain: draft.unsure("fat"))
            }
            .overlay(alignment: .top) { Hairline() }
            if !showsSplit && (draft.fiber ?? 0) > 0 {
                Button("Split fiber into soluble and insoluble") { splitFiber = true }
                    .font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.text2)
                    .frame(minHeight: 44)
            }
        }
    }

    /// A number binding that clears the field's "Check" once it is edited.
    private func field(_ path: WritableKeyPath<FoodDraft, Double?>, _ key: String) -> Binding<Double?> {
        Binding(get: { draft[keyPath: path] }, set: { v in
            guard v != draft[keyPath: path] else { return }
            draft[keyPath: path] = v
            let snake = key.reduce(into: "") { s, c in s += c.isUppercase ? "_" + c.lowercased() : String(c) }
            draft.uncertain.remove(key)
            draft.uncertain.remove(snake)
        })
    }

    private var showsSplit: Bool { splitFiber || draft.fiberSoluble != nil || draft.fiberInsoluble != nil }

    /// How the fiber setting will score this food, in the design's words.
    @ViewBuilder private var fiberNote: some View {
        if let kcal = draft.kcal, let fiber = draft.fiber, fiber > 0 {
            let adj = Ledger.fiberAdjustment(fiber: fiber, soluble: draft.fiberSoluble, insoluble: draft.fiberInsoluble,
                                             mode: ledger.fiberMode, kcal: kcal, protein: draft.protein,
                                             carbs: draft.carbs, fat: draft.fat)
            let tail = draft.micros.isEmpty ? "" : " Everything else printed on the label is saved too."
            Group {
                if adj > 0 {
                    Text("This label counts fiber at full calories, so it's logged as \(Text(Format.int(kcal - adj)).font(Typo.mono(14))).\(tail)")
                } else {
                    Text("This label already counts fiber at about 2 kcal a gram, so it's logged as printed.\(tail)")
                }
            }
            .font(.system(size: 14)).lineSpacing(3).foregroundStyle(Theme.planned)
            .padding(.top, 14)
        } else if !draft.micros.isEmpty {
            Text("Everything else printed on the label is saved too.")
                .font(.system(size: 14)).foregroundStyle(Theme.planned).padding(.top, 14)
        }
    }

    private func arithmeticCard(_ warning: String) -> some View {
        let fixed = draft.atwaterKcal ?? 0
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("The calories don't add up").font(.system(size: 15, weight: .medium))
                Spacer()
                Cap("Check", color: Theme.amber)
            }
            Text("\(warning) Using \(Text(Format.int(fixed)).font(Typo.mono(14))), worked out from the macros, keeps the fiber setting honest.")
                .font(.system(size: 14)).lineSpacing(3).foregroundStyle(Theme.planned)
            HStack(spacing: 8) {
                Button("Use \(Format.int(fixed))") {
                    if let printed = draft.kcal {
                        let note = "label prints \(Format.int(printed)) kcal, which its macros don't support"
                        draft.notes = [draft.notes, note].compactMap { $0 }.joined(separator: "; ")
                    }
                    draft.kcal = fixed
                    draft.uncertain.remove("kcal")
                }
                .buttonStyle(PrimaryButtonStyle())
                .frame(height: 44)
                Button("Use printed") { keptPrinted = true }
                    .buttonStyle(OutlineButtonStyle(height: 44, fill: true))
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14).fill(Theme.graphite))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.hairline, lineWidth: 1))
        .padding(.top, 14)
    }

    // MARK: aliases

    private var aliasList: [String] {
        draft.aliases.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    private var aliasSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Cap("Also answers to")
            ChipFlow(spacing: 6) {
                ForEach(aliasList, id: \.self) { alias in
                    Button { removeAlias(alias) } label: {
                        HStack(spacing: 6) {
                            Text(alias).font(Typo.mono(13))
                            Image(systemName: "xmark").font(.system(size: 9, weight: .semibold)).foregroundStyle(Theme.text3)
                        }
                        .padding(.horizontal, 12).frame(height: 32)
                        .background(Capsule().fill(Theme.bar))
                        .frame(minHeight: 44)
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Remove \(alias)")
                }
                TextField("", text: $newAlias, prompt: Text("add a name").foregroundStyle(Theme.text3))
                    .font(Typo.mono(13)).textInputAutocapitalization(.never).autocorrectionDisabled()
                    .submitLabel(.done)
                    .onSubmit(addAlias)
                    .padding(.horizontal, 12).frame(width: 140, height: 32)
                    .overlay(Capsule().stroke(CaptureColors.stepperBorder, lineWidth: 1))
                    .frame(minHeight: 44)
            }
        }
        .padding(.top, 18)
    }

    private func addAlias() {
        let a = newAlias.trimmingCharacters(in: .whitespaces).lowercased()
        newAlias = ""
        guard !a.isEmpty, !aliasList.contains(a) else { return }
        draft.aliases = (aliasList + [a]).joined(separator: ", ")
    }

    private func removeAlias(_ a: String) {
        draft.aliases = aliasList.filter { $0 != a }.joined(separator: ", ")
    }

    // MARK: micros

    private var microsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader(title: "Everything else on the label", trailing: draft.micros.isEmpty ? nil : "\(draft.micros.count)")
                .padding(.top, 22)
            ForEach(orderedMicros, id: \.self) { key in
                LabelFieldRow(label: NutritionLabelParser.displayName(key), value: microBinding(key),
                              unit: NutritionLabelParser.unitSuffix(key), labelColor: Theme.text2,
                              uncertain: draft.unsure(key), height: 44)
            }
            let missing = NutritionLabelParser.microKeys.filter { draft.micros[$0] == nil }
            if !missing.isEmpty {
                Menu {
                    ForEach(missing, id: \.self) { key in
                        Button(NutritionLabelParser.displayName(key)) { draft.micros[key] = 0 }
                    }
                } label: {
                    Label("Add a nutrient", systemImage: "plus")
                        .font(.system(size: 14, weight: .medium)).foregroundStyle(Theme.text2)
                        .frame(minHeight: 44)
                }
            }
            if let notes = draft.notes, !notes.isEmpty {
                Text(notes.prefix(1).uppercased() + notes.dropFirst() + ".")
                    .font(.system(size: 13)).foregroundStyle(Theme.text3).padding(.top, 4)
            }
        }
    }

    /// Label order rather than alphabetical, so the list reads like the panel.
    private var orderedMicros: [String] {
        let order = NutritionLabelParser.microKeys
        return draft.micros.keys.sorted { a, b in
            (order.firstIndex(of: a) ?? 999, a) < (order.firstIndex(of: b) ?? 999, b)
        }
    }

    private func microBinding(_ key: String) -> Binding<Double?> {
        Binding(get: { draft.micros[key] }, set: { v in
            guard v != draft.micros[key] else { return }
            draft.micros[key] = v
            draft.uncertain.remove(key)
        })
    }

    // MARK: source and raw text

    private static let sources: [(key: String, title: String)] = [
        ("label_photo", "Label photo"), ("manual", "Typed in"), ("usda", "Reference (USDA)"), ("estimate", "Estimate"),
    ]

    private var sourceSection: some View {
        HStack {
            Text("Source").font(Typo.body).foregroundStyle(Theme.text2)
            Spacer()
            Menu {
                ForEach(Self.sources, id: \.key) { s in
                    Button(s.title) { draft.source = s.key }
                }
            } label: {
                HStack(spacing: 6) {
                    Text(Self.sources.first { $0.key == draft.source }?.title ?? draft.source)
                    Image(systemName: "chevron.up.chevron.down").font(.system(size: 11))
                }
                .font(Typo.mono(14)).foregroundStyle(Theme.text)
                .frame(minHeight: 44)
            }
        }
        .overlay(alignment: .bottom) { Hairline() }
        .padding(.top, 12)
    }

    private func rawSection(_ raw: String) -> some View {
        DisclosureGroup {
            Text(raw)
                .font(Typo.mono(12)).foregroundStyle(Theme.text3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
                .padding(.top, 6)
        } label: {
            Cap("What the camera read")
        }
        .tint(Theme.text3)
        .padding(.top, 14)
    }
}

/// "Calories ········ 240" with a number field on the right. Uncertain readings get
/// an amber "Check" so they are looked at before saving.
struct LabelFieldRow: View {
    var label: String
    @Binding var value: Double?
    var unit: String
    var indent: CGFloat = 0
    var labelColor: Color = Theme.text
    var uncertain = false
    var height: CGFloat = 52

    var body: some View {
        HStack(spacing: 8) {
            Text(label).font(.system(size: 15, weight: .medium)).foregroundStyle(labelColor)
                .padding(.leading, indent)
            if uncertain { Cap("Check", color: Theme.amber) }
            Spacer()
            TextField("–", value: $value, format: .number.precision(.fractionLength(0...3)))
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .font(Typo.mono(17))
                .frame(width: 80, height: 40)
                .accessibilityLabel(label)
            Text(unit).font(Typo.mono(13)).foregroundStyle(Theme.text3).frame(width: 24, alignment: .leading)
        }
        .frame(height: height)
        .overlay(alignment: .bottom) { Hairline() }
    }
}

/// Wrapping row of chips.
struct ChipFlow: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(proposal.width ?? .infinity, subviews)
        let height = rows.map(\.height).reduce(0, +) + spacing * CGFloat(max(0, rows.count - 1))
        let width = rows.map(\.width).max() ?? 0
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(bounds.width, subviews) {
            var x = bounds.minX
            for i in row.indices {
                let size = subviews[i].sizeThatFits(.unspecified)
                subviews[i].place(at: CGPoint(x: x, y: y + (row.height - size.height) / 2), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row { var indices: [Int] = []; var width: CGFloat = 0; var height: CGFloat = 0 }

    private func arrange(_ maxWidth: CGFloat, _ subviews: Subviews) -> [Row] {
        var rows: [Row] = [Row()]
        for i in subviews.indices {
            let size = subviews[i].sizeThatFits(.unspecified)
            if !rows[rows.count - 1].indices.isEmpty, rows[rows.count - 1].width + spacing + size.width > maxWidth {
                rows.append(Row())
            }
            var r = rows[rows.count - 1]
            r.width += (r.indices.isEmpty ? 0 : spacing) + size.width
            r.height = max(r.height, size.height)
            r.indices.append(i)
            rows[rows.count - 1] = r
        }
        return rows.filter { !$0.indices.isEmpty }
    }
}
