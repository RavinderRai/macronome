import SwiftUI

/// Targets.dc.html. Step 1 of onboarding, and the targets screen from Settings, where
/// it also takes a one-day override ("Just for today").
struct TargetsView: View {
    var onboarding = false

    @Environment(FoodStore.self) private var store
    @Environment(Router.self) private var router
    @Environment(\.dismiss) private var dismiss
    @AppStorage("onboarded") private var onboarded = false

    @State private var kcal: Double? = 1700
    @State private var protein: Double? = 165
    @State private var carbs: Double? = 159
    @State private var fat: Double? = 45
    @State private var fiber: Double? = 28
    @State private var netCarbs = true
    @State private var diet: Diet?
    @State private var avoid = ""
    @State private var todayKcal: Double = 1700
    @State private var loaded = false
    @State private var saved = false

    enum Diet: String, CaseIterable, Identifiable {
        case vegan, vegetarian, everything
        var id: String { rawValue }
        var title: String { rawValue.capitalized }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text(onboarding ? "Your daily numbers" : "Daily targets")
                        .font(.system(size: 30, weight: .semibold)).tracking(-0.9)
                        .padding(.top, 4).padding(.bottom, 6)
                    Text("Change them any time. A one-day change never touches these.")
                        .font(Typo.body).foregroundStyle(Theme.text2)
                        .padding(.bottom, 18)
                    targetRows
                    sumLine
                    dietSection
                    if !onboarding { todaySection }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }
            .scrollDismissesKeyboard(.interactively)
            footer
        }
        .page()
        .onAppear(perform: load)
    }

    // MARK: header and footer

    private var header: some View {
        HStack {
            Button { dismiss() } label: {
                Image(systemName: "chevron.left").font(.system(size: 19, weight: .medium)).frame(width: 44, height: 44)
            }
            .accessibilityLabel("Back")
            if !onboarding { Text("Targets").font(.system(size: 17, weight: .semibold)) }
            Spacer()
            if onboarding { Cap("Step 1 of 2").padding(.trailing, 10) }
        }
        .padding(.horizontal, 10)
        .frame(height: 56)
    }

    private var footer: some View {
        VStack(spacing: 4) {
            if onboarding {
                Button("Continue") {
                    OnboardingSession.pending = standingEvents(all: true)
                    router.cover = .pantryScan
                }
                .buttonStyle(.primary).frame(height: 56)
                .disabled(!valid)
                Button("Skip the labels for now") {
                    OnboardingSession.pending = standingEvents(all: true)
                    onboarded = true
                    OnboardingSession.finish(store: store, router: router)
                }
                .font(.system(size: 14, weight: .medium)).foregroundStyle(Theme.text2)
                .frame(maxWidth: .infinity, minHeight: 44)
                .disabled(!valid)
            } else {
                Button(saved ? "Saved" : "Save") {
                    store.append(standingEvents(all: false))
                    saved = true
                    dismiss()
                }
                .buttonStyle(.primary).frame(height: 56)
                .disabled(!valid || standingEvents(all: false).isEmpty)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 12)
    }

    private var valid: Bool { (kcal ?? 0) > 0 && (protein ?? 0) > 0 && carbs != nil && fat != nil }

    // MARK: rows

    private var targetRows: some View {
        VStack(spacing: 0) {
            TargetRow(label: "Calories", value: $kcal, unit: "kcal", step: 50)
            TargetRow(label: "Protein", value: $protein, unit: "g", step: 5, labelColor: Theme.amber)
            TargetRow(label: netCarbs ? "Net carbs" : "Carbs", value: $carbs, unit: "g", step: 5)
            TargetRow(label: "Fat", value: $fat, unit: "g", step: 5)
            TargetRow(label: "Fiber, at least", value: $fiber, unit: "g", step: 1)
            Toggle(isOn: $netCarbs) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Count carbs as net").font(.system(size: 15, weight: .medium))
                    Text("Fiber comes off and is tracked on its own").font(.system(size: 13)).foregroundStyle(Theme.text3)
                }
            }
            .toggleStyle(PillToggleStyle())
            .frame(minHeight: 64)
            .overlay(alignment: .bottom) { Hairline() }
        }
        .overlay(alignment: .top) { Hairline() }
    }

    /// Whether the three macros land on the calorie target.
    @ViewBuilder private var sumLine: some View {
        if let p = protein, let c = carbs, let f = fat, let k = kcal {
            let sum = p * 4 + c * 4 + f * 9
            let off = abs(sum - k) > 50
            Text(off ? "Protein, carbs and fat add up to \(Format.int(sum)) kcal, \(Format.int(abs(sum - k))) \(sum > k ? "over" : "under") the calorie target."
                     : "Protein, carbs and fat add up to \(Format.int(sum)) kcal.")
                .font(Typo.mono(12)).foregroundStyle(off ? Theme.text2 : Theme.text3)
                .padding(.top, 10)
        }
    }

    private var dietSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Cap("How you eat")
            HStack(spacing: 8) {
                ForEach(Diet.allCases) { d in
                    ChoiceChip(title: d.title, selected: diet == d) { diet = d }
                }
            }
            Text("Allergies or foods to avoid").font(.system(size: 13)).foregroundStyle(Theme.text2).padding(.top, 6)
            TextField("", text: $avoid, prompt: Text("Optional").foregroundStyle(Theme.text3))
                .font(.system(size: 16))
                .padding(.horizontal, 14).frame(height: 48)
                .background(RoundedRectangle(cornerRadius: 12).fill(Theme.surface))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(CaptureColors.stepperBorder, lineWidth: 1))
        }
        .padding(.top, 20)
    }

    // MARK: just for today

    private var standing: Targets { store.ledger.standingTargets }

    /// Keep protein and fat, take the difference out of carbs (food-log/CLAUDE.md).
    private var todayCarbs: Double? {
        guard let sk = standing.kcal, let sc = standing.carbs else { return nil }
        return max(0, (sc - (sk - todayKcal) / 4).rounded())
    }

    private var todaySection: some View {
        let day = store.today
        let current = store.ledger.targets(on: day)
        let overridden = store.ledger.hasOverride(on: day)
        return VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Just for today", trailing: overridden ? "\(Format.int(current.kcal)) today" : nil)
            Text("A refeed, or making up for yesterday. Protein and fat stay; the difference comes out of carbs. Other days keep the numbers above.")
                .font(.system(size: 14)).lineSpacing(3).foregroundStyle(Theme.text2)
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Cap("Calories today")
                    Text("\(Format.int(todayKcal))\(Text(" kcal").font(Typo.mono(13)).foregroundStyle(Theme.text2))")
                        .font(.system(size: 30, weight: .medium)).tracking(-0.9).monospacedDigit()
                        .contentTransition(.numericText())
                }
                Spacer()
                RoundStepButton(systemName: "minus", label: "Lower today's calories") { todayKcal = max(0, todayKcal - 50) }
                RoundStepButton(systemName: "plus", label: "Raise today's calories") { todayKcal += 50 }
            }
            .frame(height: 68)
            if let c = todayCarbs {
                Text("\(netCarbs ? "Net carbs" : "Carbs") today \(Format.int(c)) g, protein \(Format.int(standing.protein)) g, fat \(Format.int(standing.fat)) g")
                    .font(Typo.mono(12)).foregroundStyle(Theme.text3)
            }
            HStack(spacing: 8) {
                Button("Set for today") { setToday() }
                    .buttonStyle(.primary)
                    .disabled(todayCarbs == nil || (overridden && current.kcal == todayKcal))
                if overridden {
                    Button("Back to standard") { clearToday() }
                        .buttonStyle(OutlineButtonStyle(fill: true))
                }
            }
            if standing.kcal == nil {
                Text("Save daily targets first.").font(.system(size: 13)).foregroundStyle(Theme.text3)
            }
        }
        .padding(.top, 28)
    }

    private func setToday() {
        guard let c = todayCarbs else { return }
        let day = store.today
        store.append([Commands.setTarget(.kcal, todayKcal, day: day), Commands.setTarget(.carbs, c, day: day)])
    }

    /// There is no delete for a day target, so write the standing numbers back.
    private func clearToday() {
        let day = store.today
        let s = standing
        var events: [Event] = []
        for key in [MacroStatus.Key.kcal, .protein, .carbs, .fat, .fiber] {
            if let v = s[key], store.ledger.dayTargets[day]?[key.rawValue] != nil {
                events.append(Commands.setTarget(key, v, day: day))
            }
        }
        store.append(events)
        todayKcal = s.kcal ?? todayKcal
    }

    // MARK: load and save

    private func load() {
        guard !loaded else { return }
        loaded = true
        let p = store.ledger.profile
        let s = standing
        kcal = s.kcal ?? kcal
        protein = s.protein ?? protein
        carbs = s.carbs ?? carbs
        fat = s.fat ?? fat
        fiber = s.fiber ?? fiber
        netCarbs = onboarding ? true : store.ledger.carbMode == "net"
        diet = Self.diet(from: p["diet"])
        avoid = p["allergies"] ?? ""
        todayKcal = store.ledger.targets(on: store.today).kcal ?? kcal ?? 1700
    }

    static func diet(from value: String?) -> Diet? {
        let v = (value ?? "").lowercased()
        if v.hasPrefix("vegan") { return .vegan }
        if v.hasPrefix("vegetarian") { return .vegetarian }
        if v.hasPrefix("everything") || v.hasPrefix("omnivore") { return .everything }
        return nil
    }

    /// Profile events for what changed (or everything, during onboarding). The diet note
    /// is only rewritten when the choice changes, so a longer note survives a save.
    private func standingEvents(all: Bool) -> [Event] {
        let s = standing
        let p = store.ledger.profile
        var out: [Event] = []
        let pairs: [(MacroStatus.Key, Double?, Double?)] = [
            (.kcal, kcal, s.kcal), (.protein, protein, s.protein), (.carbs, carbs, s.carbs), (.fat, fat, s.fat), (.fiber, fiber, s.fiber),
        ]
        for (key, new, old) in pairs {
            if let new, all || new != old { out.append(Commands.setTarget(key, new)) }
        }
        let mode = netCarbs ? "net" : "total"
        if all || mode != store.ledger.carbMode { out.append(Commands.setProfile("carb_mode", mode)) }
        if let diet, all || diet != Self.diet(from: p["diet"]) { out.append(Commands.setProfile("diet", diet.rawValue)) }
        let a = avoid.trimmingCharacters(in: .whitespacesAndNewlines)
        if a != (p["allergies"] ?? ""), !(a.isEmpty && p["allergies"] == nil) { out.append(Commands.setProfile("allergies", a)) }
        return out
    }
}

/// "CALORIES / 1,700 kcal ······ − +".
private struct TargetRow: View {
    var label: String
    @Binding var value: Double?
    var unit: String
    var step: Double
    var labelColor: Color = Theme.text3

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Cap(label, color: labelColor)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    TextField("–", value: $value, format: .number.precision(.fractionLength(0...1)))
                        .keyboardType(.decimalPad)
                        .font(.system(size: 30, weight: .medium)).tracking(-0.9).monospacedDigit()
                        .fixedSize()
                        .accessibilityLabel(label)
                    Text(unit).font(Typo.mono(13)).foregroundStyle(Theme.text2)
                }
            }
            Spacer()
            RoundStepButton(systemName: "minus", label: "Lower \(label.lowercased())") { value = max(0, (value ?? 0) - step) }
            RoundStepButton(systemName: "plus", label: "Raise \(label.lowercased())") { value = (value ?? 0) + step }
        }
        .frame(height: 68)
        .overlay(alignment: .bottom) { Hairline() }
    }
}
