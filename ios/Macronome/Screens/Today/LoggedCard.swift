import SwiftUI

/// The confirmation that rises over the bottom of Today after a log: what went in,
/// what is left, one line about the rest of the day, Undo and Edit.
struct LoggedCard: View {
    var receipt: FoodStore.Receipt
    var group: LogGroup
    var ledger: Ledger
    var day: String
    var habits: MealHabits
    var context: LogCoordinator.Context?
    var onUndo: () -> Void
    var onEdit: () -> Void
    var onSwap: (Entry, Food) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Cap("Logged · \(group.meal?.title ?? "Today")", color: Theme.muted)
                Spacer()
                if receipt.replacedPlan != nil { Cap("Replaced the plan", color: Theme.amber) }
            }
            HStack(alignment: .firstTextBaseline) {
                Text(group.label).font(.system(size: 22, weight: .semibold)).tracking(-0.44).lineLimit(2)
                Spacer(minLength: 12)
                Text(Format.int(group.macros.kcal)).font(Typo.mono(22))
            }
            if group.entries.count > 1 || group.entries.first?.label != group.label {
                VStack(spacing: 7) {
                    ForEach(group.entries) { e in
                        HStack(spacing: 8) {
                            Text(LogDraft.displayName(e.label)).foregroundStyle(Theme.amberText).lineLimit(1)
                            Spacer(minLength: 8)
                            Text(e.amountText).foregroundStyle(Theme.muted)
                            Text(Format.int(e.kcal)).frame(width: 40, alignment: .trailing)
                        }
                    }
                }
                .font(Typo.mono(13))
            }
            footer
            if let reading = context?.reading {
                Text(reading).font(.system(size: 13)).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true)
            }
            if let hint = hint {
                hint.font(.system(size: 14)).lineSpacing(3).foregroundStyle(Theme.amberText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let swap = alternative {
                Button { onSwap(swap.entry, swap.food) } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.left.arrow.right").font(.system(size: 12, weight: .semibold))
                        Text("\(LogDraft.displayName(swap.food.name)) instead")
                    }
                }
                .buttonStyle(AmberCardButtonStyle(filled: false, fill: false))
            }
            HStack(spacing: 8) {
                Button("Undo", action: onUndo).buttonStyle(AmberCardButtonStyle(filled: false))
                Button("Edit", action: onEdit).buttonStyle(AmberCardButtonStyle(filled: true))
            }
        }
        .foregroundStyle(Theme.text)
        .padding(18)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Theme.deepAmber))
        .shadow(color: .black.opacity(0.5), radius: 20, y: 16)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Logged \(group.label)")
    }

    private var footer: some View {
        let m = group.macros
        let carbs = ledger.carbMode == "net" ? m.netCarbs : m.carbs
        let left = ledger.macroStatus(on: day).first?.left
        return HStack {
            Text("P \(Format.int(m.protein)) · C \(Format.int(carbs)) · F \(Format.int(m.fat))").foregroundStyle(Theme.muted)
            Spacer()
            if let left {
                Text(left >= 0 ? "\(Format.int(left)) left" : "\(Format.int(-left)) over")
                    .foregroundStyle(left >= 0 ? Theme.text : Theme.coral)
            }
        }
        .font(Typo.mono(13))
        .padding(.top, 12)
        .overlay(alignment: .top) { Hairline(color: Theme.amberDivider) }
    }

    /// What the next plan, or the usual meal still to come, would do to the day.
    private var hint: Text? {
        let bank = ledger.bank ?? 0
        var name: String?
        var extra = Macros.zero
        if let plan = ledger.plans(on: day).first {
            name = plan.label
            extra = plan.macros
        } else if let meal = habits.nextUsual(ledger.sortedMeals, excluding: Set([MealHabits.meal(for: group, in: ledger.sortedMeals)?.id].compactMap { $0 })) {
            name = meal.name
            extra = ledger.preview(meal)
        }
        let leftNow = ledger.macroStatus(on: day).first?.left ?? 0
        guard let name else {
            guard leftNow < 0 else { return nil }
            return bank > 0 ? Text("The bank has \(mono(Format.trim(bank))) if you want it.") : nil
        }
        guard let after = ledger.macroStatus(on: day, extra: extra).first?.left else { return nil }
        let subject = "The " + Self.sentenceCase(name)
        if after >= 0 {
            return Text("\(subject) would still leave \(mono(Format.int(after))).")
        }
        let over = Text("\(subject) would put you \(mono(Format.int(-after))) over.")
        return bank > 0 ? Text("\(over) The bank has \(mono(Format.trim(bank))) if you want it.") : over
    }

    private func mono(_ s: String) -> Text { Text(s).font(Typo.mono(14)) }

    /// The first alternative the parser passed over, offered as a one-tap swap.
    private var alternative: (entry: Entry, food: Food)? {
        guard let alts = context?.alternatives else { return nil }
        for e in group.entries {
            if let fid = e.foodID, let first = alts[fid]?.first, let food = ledger.foods[first] { return (e, food) }
        }
        return nil
    }

    /// "Evening bowl" -> "evening bowl" for use mid-sentence; names with capitals inside
    /// ("PC penne") are left alone.
    static func sentenceCase(_ s: String) -> String {
        let words = s.split(separator: " ")
        guard let first = words.first, first.dropFirst().allSatisfy({ !$0.isUppercase }) else { return s }
        return s.prefix(1).lowercased() + s.dropFirst()
    }
}

/// Words that did not match anything: offer to add a food or ask.
struct LeftoverCard: View {
    var leftover: LogCoordinator.Leftover
    var onAdd: (String) -> Void
    var onAsk: () -> Void
    var onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Cap("Not in your foods")
                    Text(leftover.phrases.map { "“\($0)”" }.joined(separator: ", "))
                        .font(.system(size: 16, weight: .medium)).lineLimit(2)
                }
                Spacer()
                Button(action: onClose) { RoundIcon(systemName: "xmark", size: 36) }
                    .accessibilityLabel("Dismiss")
            }
            HStack(spacing: 8) {
                Button("Add as a new food") { onAdd(leftover.phrases.first ?? leftover.text) }
                    .buttonStyle(OutlineButtonStyle(height: 44, fill: true))
                Button("Ask in chat", action: onAsk)
                    .buttonStyle(OutlineButtonStyle(border: Theme.tick, height: 44, fill: true))
            }
        }
        .foregroundStyle(Theme.text)
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Theme.surface))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(Theme.hairline))
        .shadow(color: .black.opacity(0.4), radius: 14, y: 10)
    }
}

/// Pill buttons on deep amber: outlined in amber-brown, or filled a step lighter.
struct AmberCardButtonStyle: ButtonStyle {
    var filled: Bool
    var height: CGFloat = 44
    var fill = true
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: height < 48 ? 14 : 15, weight: .semibold))
            .padding(.horizontal, 16)
            .frame(maxWidth: fill ? .infinity : nil, minHeight: height)
            .background(Capsule().fill(filled ? Theme.deepAmber2 : .clear))
            .overlay(Capsule().stroke(filled ? .clear : Theme.amberDivider, lineWidth: 1))
            .foregroundStyle(Theme.text)
            .contentShape(Capsule())
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}
