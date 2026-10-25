import SwiftUI

/// The food library: usual meals, then foods by how often they are logged.
struct FoodsView: View {
    @Environment(FoodStore.self) private var store
    @Environment(Router.self) private var router
    @State private var query = ""
    @State private var command = ""

    var body: some View {
        let ledger = store.ledger
        let meals = ledger.libMeals(query)
        let foods = ledger.libFoodsByUse(query)
        let counts = ledger.libUseCounts

        VStack(spacing: 0) {
            TopNav()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    LibSearchField(text: $query,
                                   prompt: "Search \(ledger.foods.count) foods and \(ledger.meals.count) meals")

                    if !meals.isEmpty {
                        VStack(spacing: 0) {
                            SectionHeader(title: "Usual meals", trailing: "kcal")
                            ForEach(meals) { meal in
                                Button { router.push(.meal(meal.id)) } label: { mealRow(meal, ledger: ledger) }
                                    .buttonStyle(.plain)
                            }
                        }
                    }

                    if !foods.isEmpty {
                        VStack(spacing: 0) {
                            SectionHeader(title: query.isEmpty ? "Foods · most used" : "Foods", trailing: "Times")
                            ForEach(foods) { food in
                                Button { router.push(.food(food.id)) } label: {
                                    foodRow(food, count: counts[food.id] ?? 0, ledger: ledger)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    if meals.isEmpty && foods.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text(query.isEmpty ? "No foods yet." : "Nothing called “\(query)” yet.")
                                .font(Typo.body).foregroundStyle(Theme.text2)
                            Text("Check the spelling first, so the library doesn't end up with two of the same food.")
                                .font(.system(size: 13)).foregroundStyle(Theme.text3)
                        }
                        .padding(.top, 8)
                    }

                    addButtons
                }
                .padding(.horizontal, 20)
                .padding(.top, 4)
                .padding(.bottom, 24)
            }
            .scrollDismissesKeyboard(.interactively)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                CommandBar(text: $command, placeholder: "Describe a meal to save it",
                           onSubmit: { text in
                               router.sheet = .chat(prompt: "Save this as a usual meal: \(text)")
                               command = ""
                           },
                           onCamera: { router.cover = .labelScan },
                           onMic: { router.sheet = .listening })
            }
        }
        .page()
    }

    private func mealRow(_ meal: UsualMeal, ledger: Ledger) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(meal.name).font(Typo.row).lineLimit(1)
                Text(ledger.libComponentLine(meal)).font(.system(size: 13)).foregroundStyle(Theme.text3).lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(Format.int(ledger.preview(meal).kcal)).font(Typo.mono(15))
        }
        .frame(minHeight: 56)
        .overlay(alignment: .bottom) { Hairline() }
        .contentShape(Rectangle())
    }

    private func foodRow(_ food: Food, count: Int, ledger: Ledger) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(food.name).font(Typo.row).lineLimit(1)
                Text(ledger.libBasisLine(food)).font(Typo.mono(12)).foregroundStyle(Theme.text3).lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(count > 0 ? "\(count)" : "–").font(Typo.mono(14)).foregroundStyle(Theme.text2)
        }
        .frame(minHeight: 56)
        .overlay(alignment: .bottom) { Hairline() }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint(count == 1 ? "Logged once" : "Logged \(count) times")
    }

    private var addButtons: some View {
        VStack(alignment: .leading, spacing: 10) {
            Cap("Add")
            LibFlow(spacing: 8) {
                Button {
                    var draft = FoodDraft()
                    draft.name = query.trimmingCharacters(in: .whitespaces)
                    router.push(.newFood(draft))
                } label: { Label("New food", systemImage: "plus") }
                Button { router.cover = .labelScan } label: { Label("Scan a label", systemImage: "camera") }
                Button { router.push(.newMeal) } label: { Label("New meal", systemImage: "square.stack") }
            }
            .buttonStyle(LibPillStyle())
            .labelStyle(.titleAndIcon)
        }
        .padding(.top, 4)
    }
}
