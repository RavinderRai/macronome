import SwiftUI

/// PantryReview.dc.html: every label read in the pantry scan, to name and check before
/// they all go into the library at once.
struct PantryReviewView: View {
    @Environment(FoodStore.self) private var store
    @Environment(Router.self) private var router
    @Environment(\.dismiss) private var dismiss
    @AppStorage("onboarded") private var onboarded = false

    @State private var items: [FoodDraft]
    @State private var editing: FoodDraft.ID?
    /// Labels whose printed calories were kept despite the arithmetic.
    @State private var keptPrinted: Set<FoodDraft.ID> = []

    init(drafts: [FoodDraft]) {
        _items = State(initialValue: drafts)
    }

    private var ready: [FoodDraft] { items.filter(\.isComplete) }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button { scanMore() } label: {
                    Image(systemName: "chevron.left").font(.system(size: 19, weight: .medium)).frame(width: 44, height: 44)
                }
                .accessibilityLabel("Back to camera")
                Spacer()
                Cap("Step 2 of 2").padding(.trailing, 10)
            }
            .padding(.horizontal, 10)
            .frame(height: 56)

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Check what was read").font(.system(size: 30, weight: .semibold)).tracking(-0.9)
                        .padding(.top, 4).padding(.bottom, 6)
                    Text("Read off each label. Tap a food to fix a number or give it a name.")
                        .font(Typo.body).lineSpacing(3).foregroundStyle(Theme.text2)
                        .padding(.bottom, 16)
                    VStack(spacing: 0) {
                        ForEach(items) { d in
                            if needsCard(d) { card(d) } else { row(d) }
                        }
                    }
                    .overlay(alignment: .top) { Hairline() }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }

            VStack(spacing: 4) {
                Button(ready.isEmpty ? "Finish" : "Add \(ready.count) food\(ready.count == 1 ? "" : "s")") { saveAll() }
                    .buttonStyle(.primary).frame(height: 56)
                if items.count > ready.count && !ready.isEmpty {
                    Text("\(items.count - ready.count) still need a name or numbers and won't be added.")
                        .font(.system(size: 13)).foregroundStyle(Theme.text3)
                }
                Button("Scan more labels") { scanMore() }
                    .font(.system(size: 14, weight: .medium)).foregroundStyle(Theme.text2)
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .padding(.horizontal, 20).padding(.top, 8).padding(.bottom, 12)
        }
        .page()
        .sheet(item: editingBinding) { box in
            DraftEditSheet(draft: binding(for: box.id), ledger: store.ledger) {
                items.removeAll { $0.id == box.id }
                editing = nil
            }
        }
    }

    // MARK: rows

    private func subtitle(_ d: FoodDraft) -> String {
        var parts: [String] = []
        if d.basis == .per100g { parts.append("100 g") } else if let l = d.servingLabel, l != "serving" { parts.append("1 \(l)") } else if let g = d.servingGrams {
            parts.append("\(Format.trim(g)) g")
        } else { parts.append("1 serving") }
        if let p = d.protein { parts.append("P \(Format.trim(p))") }
        if let c = d.carbs { parts.append("C \(Format.trim(c))") }
        if let f = d.fat { parts.append("F \(Format.trim(f))") }
        if let fb = d.fiber, fb > 0 { parts.append("fiber \(Format.trim(fb))") }
        return parts.joined(separator: " · ")
    }

    private func needsCard(_ d: FoodDraft) -> Bool {
        d.name.trimmingCharacters(in: .whitespaces).isEmpty || !d.isComplete
            || (d.labelArithmeticWarning != nil && !keptPrinted.contains(d.id))
    }

    private func row(_ d: FoodDraft) -> some View {
        Button { editing = d.id } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(d.name).font(.system(size: 15, weight: .medium)).lineLimit(1)
                        if !d.uncertain.isEmpty { Cap("Check", color: Theme.amber) }
                    }
                    Text(subtitle(d)).font(Typo.mono(12)).foregroundStyle(Theme.text3).lineLimit(1)
                }
                Spacer(minLength: 8)
                Text(Format.int(d.kcal)).font(Typo.mono(15))
            }
            .frame(minHeight: 68)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .bottom) { Hairline() }
    }

    private func card(_ d: FoodDraft) -> some View {
        let unnamed = d.name.trimmingCharacters(in: .whitespaces).isEmpty
        return VStack(alignment: .leading, spacing: 12) {
            Button { editing = d.id } label: {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(unnamed ? "Name this food" : d.name)
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(unnamed ? Theme.text2 : Theme.text)
                        Text(subtitle(d)).font(Typo.mono(12)).foregroundStyle(Theme.text3)
                    }
                    Spacer(minLength: 8)
                    Cap("Check", color: Theme.amber).padding(.top, 3)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if let fixed = d.atwaterKcal, d.labelArithmeticWarning != nil, !keptPrinted.contains(d.id) {
                Text("The printed calories don't add up from the macros on the same label. Using \(Text(Format.int(fixed)).font(Typo.mono(14))), worked out from the macros.")
                    .font(.system(size: 14)).lineSpacing(3).foregroundStyle(Theme.planned)
                HStack(spacing: 8) {
                    Button("Use \(Format.int(fixed))") { useAtwater(d.id) }
                        .buttonStyle(PrimaryButtonStyle()).frame(height: 44)
                    Button("Use printed") { keptPrinted.insert(d.id) }
                        .buttonStyle(OutlineButtonStyle(height: 44, fill: true))
                }
            } else if !d.isComplete {
                Text(unnamed && d.kcal != nil ? "Read \(d.readSummary). Give it a name to add it." : "Some numbers didn't come through. Tap to fill them in.")
                    .font(.system(size: 14)).lineSpacing(3).foregroundStyle(Theme.planned)
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14).fill(Theme.surface))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.hairline, lineWidth: 1))
        .padding(.top, 12)
    }

    // MARK: actions

    private func useAtwater(_ id: FoodDraft.ID) {
        guard let i = items.firstIndex(where: { $0.id == id }), let fixed = items[i].atwaterKcal else { return }
        if let printed = items[i].kcal {
            let note = "label prints \(Format.int(printed)) kcal, which its macros don't support"
            items[i].notes = [items[i].notes, note].compactMap { $0 }.joined(separator: "; ")
        }
        items[i].kcal = fixed
        items[i].uncertain.remove("kcal")
    }

    private func saveAll() {
        let events = ready.map { Commands.addFood($0.food()) }
        onboarded = true
        OnboardingSession.finish(store: store, router: router, extra: events)
    }

    private func scanMore() {
        OnboardingSession.drafts = items
        dismiss()
        router.cover = .pantryScan
    }

    // MARK: editing

    private struct Box: Identifiable { var id: FoodDraft.ID }

    private var editingBinding: Binding<Box?> {
        Binding(get: { editing.map { Box(id: $0) } }, set: { editing = $0?.id })
    }

    private func binding(for id: FoodDraft.ID) -> Binding<FoodDraft> {
        Binding(get: { items.first { $0.id == id } ?? FoodDraft() }, set: { new in
            if let i = items.firstIndex(where: { $0.id == id }) { items[i] = new }
        })
    }
}

/// The new-food form in a sheet, for fixing one read in the pantry review.
private struct DraftEditSheet: View {
    @Binding var draft: FoodDraft
    var ledger: Ledger
    var onRemove: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button("Remove", role: .destructive) { onRemove() }
                    .font(.system(size: 15, weight: .medium)).foregroundStyle(Theme.text2)
                    .frame(minHeight: 44)
                Spacer()
                Cap("Check the label")
                Spacer()
                Button("Done") { dismiss() }
                    .font(.system(size: 15, weight: .semibold))
                    .frame(minHeight: 44)
            }
            .padding(.horizontal, 20)
            .frame(height: 56)
            ScrollView {
                FoodDraftEditor(draft: $draft, ledger: ledger, onOpenExisting: nil)
                    .padding(.horizontal, 20).padding(.bottom, 24)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .background(Theme.surface.ignoresSafeArea())
        .foregroundStyle(Theme.text)
        .presentationDragIndicator(.visible)
    }
}
