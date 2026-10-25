import SwiftUI

// Small pieces shared by the library, history and settings screens. Names carry a
// `Lib` prefix so they never collide with what other screens add.

extension Theme {
    /// Field and pill outline from the Foods and FoodDetail artboards.
    static let libBorder = Color(hex: 0x3A3B37)
}

// MARK: - ledger helpers

extension Ledger {
    /// How many entries point at each food id.
    var libUseCounts: [String: Int] {
        var out: [String: Int] = [:]
        for e in entries { if let f = e.foodID { out[f, default: 0] += 1 } }
        return out
    }

    /// Foods matching a query, most logged first, then by name.
    func libFoodsByUse(_ query: String = "") -> [Food] {
        let counts = libUseCounts
        return searchFoods(query).sorted {
            (counts[$0.id] ?? 0, $1.name.lowercased()) > (counts[$1.id] ?? 0, $0.name.lowercased())
        }
    }

    /// Usual meals matching a query, in slot order (breakfast first).
    func libMeals(_ query: String = "") -> [UsualMeal] {
        let q = Self.norm(query)
        return sortedMeals
            .filter { q.isEmpty || Self.norm($0.name).contains(q) || $0.aliases.contains { Self.norm($0).contains(q) } }
            .sorted { (Self.slotOrder($0.slot), $0.name) < (Self.slotOrder($1.slot), $1.name) }
    }

    /// Meals that use a food.
    func libMeals(using foodID: String) -> [UsualMeal] {
        sortedMeals.filter { $0.components.contains { $0.foodID == foodID } }
    }

    /// The unit to log a food by the serving, or nil when it can only be weighed.
    static func libServingUnit(_ food: Food) -> String? {
        if food.basis == .per100g && (food.servingGrams ?? 0) <= 0 { return nil }
        let label = (food.servingLabel ?? "").trimmingCharacters(in: .whitespaces).lowercased()
        if !label.isEmpty, (try? resolveAmount(food, qty: 1, unit: label)) != nil { return label }
        return "serving"
    }

    static func libCanWeigh(_ food: Food) -> Bool { food.basis == .per100g || (food.servingGrams ?? 0) > 0 }

    /// The amount a food's numbers are stated for: 1 cup, or 100 g.
    static func libBasisAmount(_ food: Food) -> (qty: Double, unit: String) {
        if food.basis == .per100g { return (100, "g") }
        return (1, libServingUnit(food) ?? "serving")
    }

    /// "1 cup · 140 kcal · 13 g P", after the fiber setting.
    func libBasisLine(_ food: Food) -> String {
        let a = Self.libBasisAmount(food)
        let m = preview(food, qty: a.qty, unit: a.unit) ?? food.macros
        var parts = [Format.amount(qty: a.qty, unit: a.unit), "\(Format.int(m.kcal)) kcal"]
        if m.protein >= 2 { parts.append("\(Format.int(m.protein)) g P") }
        return parts.joined(separator: " · ")
    }

    /// "Cinnamon crisps · protein · milk".
    func libComponentLine(_ meal: UsualMeal) -> String {
        let names = meal.components.compactMap { foods[$0.foodID].map { Format.shortName($0.name) } }
        if names.isEmpty { return meal.note ?? "No components yet" }
        return names.joined(separator: " · ")
    }
}

// MARK: - micronutrients

enum LibMicro {
    /// The label keys from food-log/CLAUDE.md, in the order a label prints them.
    static let order = [
        "sat_fat_g", "trans_fat_g", "cholesterol_mg", "sodium_mg", "sugar_g", "added_sugar_g",
        "potassium_mg", "calcium_mg", "iron_mg", "magnesium_mg", "zinc_mg", "phosphorus_mg",
        "vitamin_a_ug", "vitamin_c_mg", "vitamin_d_ug", "vitamin_e_mg", "vitamin_k_ug", "thiamin_mg",
        "riboflavin_mg", "niacin_mg", "vitamin_b6_mg", "folate_ug", "vitamin_b12_ug", "omega3_g", "caffeine_mg",
    ]
    static let names: [String: String] = [
        "sat_fat": "Saturated fat", "trans_fat": "Trans fat", "sugar": "Sugars", "added_sugar": "Added sugars",
        "omega3": "Omega-3", "vitamin_b6": "Vitamin B6", "vitamin_b12": "Vitamin B12",
    ]
    static let units: Set<String> = ["g", "mg", "ug", "mcg", "iu"]

    static func label(_ key: String) -> (name: String, unit: String) {
        var parts = key.split(separator: "_").map(String.init)
        var unit = ""
        if parts.count > 1, let last = parts.last, units.contains(last) {
            unit = last == "ug" || last == "mcg" ? "µg" : last == "iu" ? "IU" : last
            parts.removeLast()
        }
        let base = parts.joined(separator: "_")
        if let n = names[base] { return (n, unit) }
        var name = parts.joined(separator: " ")
        if name.hasPrefix("vitamin ") { name = "Vitamin " + name.dropFirst(8).uppercased() }
        return (name.prefix(1).uppercased() + name.dropFirst(), unit)
    }

    static func sorted(_ micros: [String: Double]) -> [(key: String, value: Double)] {
        micros.map { ($0.key, $0.value) }.sorted { a, b in
            let ia = order.firstIndex(of: a.key) ?? Int.max, ib = order.firstIndex(of: b.key) ?? Int.max
            return (ia, a.key) < (ib, b.key)
        }
    }

    static func value(_ v: Double) -> String { Format.trim(v, digits: v < 10 ? 1 : 0) }
}

// MARK: - views

/// Rounded search input from the Foods artboard.
struct LibSearchField: View {
    @Binding var text: String
    var prompt: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").font(.system(size: 16)).foregroundStyle(Theme.text3)
            TextField("", text: $text, prompt: Text(prompt).foregroundStyle(Theme.text3))
                .font(.system(size: 16))
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .submitLabel(.search)
            if !text.isEmpty {
                Button { text = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.text3).frame(width: 36, height: 44)
                }
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.leading, 14).padding(.trailing, 6)
        .frame(height: 48)
        .background(Capsule().fill(Theme.surface))
        .overlay(Capsule().stroke(Theme.libBorder, lineWidth: 1))
    }
}

/// 40 pt radio pill ("1 cup · 40 g", "¾ cup") and link chips ("Evening bowl").
struct LibPillStyle: ButtonStyle {
    var selected = false
    var filled = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: selected ? .semibold : .medium))
            .padding(.horizontal, 14)
            .frame(height: 40)
            .background(Capsule().fill(selected ? Theme.text : filled ? Theme.surface : .clear))
            .overlay(Capsule().stroke(selected ? .clear : Theme.libBorder, lineWidth: 1))
            .foregroundStyle(selected ? Theme.graphite : Theme.text)
            .contentShape(Capsule())
            .frame(minHeight: 44)
            .opacity(configuration.isPressed ? 0.75 : 1)
    }
}

/// Mono alias tag.
struct LibTag: View {
    var text: String
    var body: some View {
        Text(text).font(Typo.mono(13)).padding(.horizontal, 12).frame(height: 30)
            .background(Capsule().fill(Theme.bar))
    }
}

/// Wraps children onto new lines, for tags.
struct LibFlow: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews: subviews)
        let h = rows.reduce(0) { $0 + $1.height } + CGFloat(max(0, rows.count - 1)) * spacing
        let w = rows.map(\.width).max() ?? 0
        return CGSize(width: proposal.width ?? w, height: h)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(width: bounds.width, subviews: subviews) {
            var x = bounds.minX
            for i in row.items {
                let s = subviews[i].sizeThatFits(.unspecified)
                subviews[i].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(s))
                x += s.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row { var items: [Int] = []; var width: CGFloat = 0; var height: CGFloat = 0 }

    private func arrange(width: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = [Row()]
        for i in subviews.indices {
            let s = subviews[i].sizeThatFits(.unspecified)
            if !rows[rows.count - 1].items.isEmpty, rows[rows.count - 1].width + spacing + s.width > width {
                rows.append(Row())
            }
            var r = rows[rows.count - 1]
            r.width += (r.items.isEmpty ? 0 : spacing) + s.width
            r.height = max(r.height, s.height)
            r.items.append(i)
            rows[rows.count - 1] = r
        }
        return rows.filter { !$0.items.isEmpty }
    }
}

/// Settings-style row: title, optional subtitle, trailing value, hairline under.
struct LibRow<Trailing: View>: View {
    var title: String
    var subtitle: String?
    var minHeight: CGFloat = 52
    var titleColor: Color = Theme.text
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 15, weight: .medium)).foregroundStyle(titleColor)
                if let subtitle { Text(subtitle).font(.system(size: 13)).foregroundStyle(Theme.text3) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            trailing
        }
        .frame(minHeight: subtitle == nil ? minHeight : max(minHeight, 64))
        .overlay(alignment: .bottom) { Hairline() }
        .contentShape(Rectangle())
    }
}

extension LibRow where Trailing == Text {
    init(_ title: String, value: String, subtitle: String? = nil, mono: Bool = false) {
        self.title = title
        self.subtitle = subtitle
        self.trailing = Text(value).font(mono ? Typo.mono(13) : .system(size: 14)).foregroundStyle(Theme.text2)
    }
}

/// A labelled text field row matching NumberField.
struct LibTextField: View {
    var label: String
    @Binding var text: String
    var prompt = ""
    var body: some View {
        HStack(spacing: 12) {
            Text(label).font(Typo.body).foregroundStyle(Theme.text2)
            Spacer(minLength: 8)
            TextField("", text: $text, prompt: Text(prompt).foregroundStyle(Theme.text3))
                .multilineTextAlignment(.trailing)
                .font(.system(size: 15))
        }
        .frame(minHeight: 48)
        .overlay(alignment: .bottom) { Hairline() }
    }
}

/// The big kcal numeral with its caption, ruled underneath (FoodDetail, MealDetail).
struct LibNumeral<Caption: View>: View {
    var kcal: Double
    @ViewBuilder var caption: Caption
    var body: some View {
        HStack(alignment: .bottom) {
            Text(Format.int(kcal)).numeralStyle(64).lineLimit(1).contentTransition(.numericText(value: kcal))
            Spacer()
            caption.font(Typo.mono(13)).foregroundStyle(Theme.text2).padding(.bottom, 4)
        }
        .padding(.top, 22).padding(.bottom, 14)
        .overlay(alignment: .bottom) { Hairline(color: Theme.text) }
        .animation(.snappy, value: kcal)
    }
}

/// Sheet chrome used for small editors: title, cancel, done.
struct LibSheet<Content: View>: View {
    var title: String
    var done: String = "Save"
    var canSave = true
    var onSave: () -> Void
    @ViewBuilder var content: Content
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Button("Cancel") { dismiss() }.foregroundStyle(Theme.text2).frame(minHeight: 44)
                Spacer()
                Text(title).font(.system(size: 17, weight: .semibold))
                Spacer()
                Button(done) { onSave(); dismiss() }
                    .fontWeight(.semibold)
                    .foregroundStyle(canSave ? Theme.text : Theme.text3)
                    .disabled(!canSave)
                    .frame(minHeight: 44)
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) { content }
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                    .padding(.bottom, 24)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .foregroundStyle(Theme.text)
        .presentationBackground(Theme.surface)
        .presentationDragIndicator(.visible)
    }
}
