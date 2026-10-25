import SwiftUI

/// Today: calories left, macros, the day's log by meal, plans, and the command bar.
struct TodayView: View {
    @Environment(FoodStore.self) private var store
    @Environment(Router.self) private var router
    @Environment(AppServices.self) private var services
    @Environment(\.scenePhase) private var scenePhase

    @State private var day = Clock.dayString()
    @State private var text = ""
    @State private var habitsCache = HabitsCache()
    @State private var justLogged: String?
    @State private var pendingDelete: LogGroup?

    private var coordinator: LogCoordinator { .shared }

    var body: some View {
        let ledger = store.ledger
        let habits = habitsCache.habits(ledger, day: day)
        VStack(spacing: 0) {
            TopNav()
            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    summary(ledger)
                    log(ledger)
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)
            .onScrollPhaseChange { _, phase in
                if phase == .interacting { dismissCard() }
            }
            .simultaneousGesture(TapGesture().onEnded { dismissCard() })
            .safeAreaInset(edge: .bottom, spacing: 0) { bottom(ledger, habits: habits) }
        }
        .page()
        .task(id: day) { await rollOverAtMidnight() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { day = Clock.dayString() }
        }
        .onChange(of: store.receipt?.id) { _, _ in
            if let gid = store.receipt?.groupID { justLogged = gid }
        }
        .task(id: cardTimerKey) {
            // The card leaves on its own after a while, but not while it is being edited.
            guard store.receipt != nil, router.sheet == nil else { return }
            try? await Task.sleep(for: .seconds(8))
            guard !Task.isCancelled else { return }
            withAnimation(.snappy) { store.dismissReceipt() }
        }
        .task(id: justLogged) {
            guard justLogged != nil else { return }
            try? await Task.sleep(for: .seconds(90))
            if !Task.isCancelled { justLogged = nil }
        }
        .confirmationDialog(pendingDelete.map { "Delete \($0.label)?" } ?? "", isPresented: deleteBinding,
                            titleVisibility: .visible, presenting: pendingDelete) { group in
            Button(group.entries.count > 1 ? "Delete \(group.entries.count) entries" : "Delete entry", role: .destructive) {
                delete(group)
            }
        } message: { group in
            Text(group.entries.map { "\(LogDraft.displayName($0.label)) · \($0.amountText) · \(Format.int($0.kcal)) kcal" }
                .joined(separator: "\n"))
        }
    }

    // MARK: summary

    @ViewBuilder private func summary(_ ledger: Ledger) -> some View {
        let status = ledger.macroStatus(on: day)
        let kcal = status.first { $0.key == .kcal }
        let plans = ledger.plans(on: day)
        let planned = ledger.plannedMacros(on: day)
        if let kcal, let target = kcal.target {
            CaloriesHeader(
                day: day, dayNumber: ledger.dayNumber(day), bank: ledger.bank, left: kcal.left ?? 0,
                eaten: kcal.eaten, target: target,
                afterPlan: plans.isEmpty ? nil : ledger.macroStatus(on: day, extra: planned).first?.left,
                segments: ledger.stripSegments(on: day))
            MacroColumns(rows: status, planned: plans.isEmpty ? nil : planned)
        } else {
            noTargets(eaten: kcal?.eaten ?? 0, ledger: ledger)
        }
    }

    private func noTargets(eaten: Double, ledger: Ledger) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Cap(ledger.dayNumber(day).map { "\(Format.dayHeader(day)) · Day \($0)" } ?? Format.dayHeader(day))
            HStack(alignment: .bottom) {
                Text(Format.int(eaten)).numeralStyle(100).lineLimit(1).minimumScaleFactor(0.6)
                Spacer()
                Text("kcal eaten").font(.system(size: 16, weight: .medium)).padding(.bottom, 4)
            }
            Text("Set daily targets to see what's left and how the day is tracking.")
                .font(Typo.body).foregroundStyle(Theme.text2)
            Button("Set targets") { router.push(.targets(onboarding: false)) }
                .buttonStyle(OutlineButtonStyle(height: 44))
        }
    }

    // MARK: log

    @ViewBuilder private func log(_ ledger: Ledger) -> some View {
        let groups = ledger.groups(on: day)
        let plans = ledger.plans(on: day)
        if groups.isEmpty && plans.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                SectionHeader(title: "Today", trailing: nil)
                Text("Nothing logged yet today.").font(Typo.row).padding(.top, 10)
                Text("Say what you ate, type it, or tap a usual meal below.")
                    .font(Typo.body).foregroundStyle(Theme.text3)
            }
        } else {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(sections(groups).enumerated()), id: \.offset) { index, section in
                    SectionHeader(title: section.slot?.title ?? "Other", trailing: Format.int(section.kcal))
                        .padding(.top, index == 0 ? 0 : 18)
                    ForEach(section.groups) { group in
                        row(group, ledger: ledger)
                    }
                }
                if !plans.isEmpty {
                    SectionHeader(title: "Planned", trailing: Format.int(ledger.plannedMacros(on: day).kcal), rule: false)
                        .padding(.top, groups.isEmpty ? 0 : 18)
                        .padding(.bottom, 2)
                    VStack(spacing: 6) {
                        ForEach(plans) { plan in
                            PlannedRow(plan: plan) { ateIt(plan, ledger: ledger) }
                                .contextMenu {
                                    Button("Remove from plan", systemImage: "minus.circle") {
                                        store.append(Commands.deletePlan(plan.id))
                                    }
                                }
                        }
                    }
                }
            }
        }
    }

    private func row(_ group: LogGroup, ledger: Ledger) -> some View {
        let highlighted = group.id == justLogged
        return Button { router.push(.entry(group.id)) } label: {
            EntryRow(group: group, justLogged: highlighted)
                .padding(.top, highlighted ? 6 : 0)
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Edit", systemImage: "slider.horizontal.3") { router.sheet = .editGroup(group.id) }
            Menu("Move to", systemImage: "arrow.turn.down.right") {
                ForEach(MealSlot.allCases.filter { $0 != group.meal }) { slot in
                    Button(slot.title) { store.replace(group: group, with: GroupEdits.move(group, to: slot, ledger: ledger)) }
                }
            }
            Button("Log again", systemImage: "arrow.counterclockwise") {
                store.log(GroupEdits.logAgain(group, ledger: ledger))
            }
            Button("Delete", systemImage: "trash", role: .destructive) { pendingDelete = group }
        }
    }

    private struct Section {
        var slot: MealSlot?
        var groups: [LogGroup]
        var kcal: Double { groups.reduce(0) { $0 + $1.macros.kcal } }
    }

    /// Groups by meal slot, sections in the order they were first eaten, so an evening
    /// snack after dinner sits under dinner rather than before it.
    private func sections(_ groups: [LogGroup]) -> [Section] {
        var out: [Section] = []
        for g in groups {
            if let i = out.firstIndex(where: { $0.slot == g.meal }) { out[i].groups.append(g) }
            else { out.append(Section(slot: g.meal, groups: [g])) }
        }
        return out
    }

    // MARK: bottom

    private func bottom(_ ledger: Ledger, habits: MealHabits) -> some View {
        let receipt = store.receipt
        let group = receipt.flatMap { ledger.group(id: $0.groupID) }
        return VStack(spacing: 8) {
            if let leftover = coordinator.leftover {
                LeftoverCard(leftover: leftover,
                             onAdd: { name in
                                 var draft = FoodDraft()
                                 draft.name = name
                                 coordinator.leftover = nil
                                 router.push(.newFood(draft))
                             },
                             onAsk: {
                                 coordinator.leftover = nil
                                 router.sheet = .chat(prompt: leftover.text)
                             },
                             onClose: { withAnimation(.snappy) { coordinator.leftover = nil } })
                    .padding(.horizontal, 12)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            if let receipt, let group {
                LoggedCard(receipt: receipt, group: group, ledger: ledger, day: day, habits: habits,
                           context: coordinator.context(for: group.id),
                           onUndo: {
                               coordinator.forget(group.id)
                               justLogged = nil
                               withAnimation(.snappy) { store.undoReceipt() }
                           },
                           onEdit: { router.sheet = .editGroup(group.id) },
                           onSwap: { entry, food in
                               store.replace(group: group, with: GroupEdits.swap(group, entryID: entry.id, to: food, ledger: ledger))
                           })
                    .padding(.horizontal, 12)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            CommandBar(text: $text, chips: group == nil ? chips(ledger, habits: habits) : [],
                       busy: coordinator.isWorking,
                       onSubmit: submit,
                       onCamera: { router.cover = .labelScan },
                       onMic: { router.sheet = .listening },
                       onChip: { chip($0, ledger: ledger) })
        }
        .animation(.snappy, value: receipt?.id)
        .animation(.snappy, value: coordinator.leftover?.id)
    }

    private func chips(_ ledger: Ledger, habits: MealHabits) -> [CommandBar.Chip] {
        let chat = CommandBar.Chip(id: "chat", title: chatPrompt(habits), isChat: true)
        let meals = habits.ranked(ledger.sortedMeals).prefix(5).map {
            CommandBar.Chip(id: $0.id, title: $0.name, kcal: ledger.preview($0).kcal)
        }
        return [chat] + meals
    }

    /// The chat chip asks about the next meal still to come.
    private func chatPrompt(_ habits: MealHabits) -> String {
        let hour = Calendar.current.component(.hour, from: Date())
        let logged = habits.slotsToday
        if hour < 10, !logged.contains(.breakfast) { return "What's for breakfast?" }
        if hour < 14, !logged.contains(.lunch) { return "Ideas for lunch?" }
        if hour < 21, !logged.contains(.dinner) { return "What's for dinner?" }
        return "Room for a snack?"
    }

    // MARK: actions

    private func submit(_ input: String) {
        text = ""
        Task {
            await coordinator.submit(input, source: .text, store: store, router: router, models: services.models)
        }
    }

    private func chip(_ chip: CommandBar.Chip, ledger: Ledger) {
        if chip.isChat {
            router.sheet = .chat(prompt: chip.title)
            return
        }
        guard let meal = ledger.meals[chip.id] else { return }
        coordinator.logMeal(meal, store: store)
    }

    private func ateIt(_ plan: PlannedItem, ledger: Ledger) {
        store.log(GroupEdits.ateIt(plan, ledger: ledger), replacing: plan)
    }

    private func delete(_ group: LogGroup) {
        if store.receipt?.groupID == group.id { store.dismissReceipt() }
        store.append(group.entries.map { Commands.deleteEntry($0.id) })
        pendingDelete = nil
    }

    private func dismissCard() {
        guard store.receipt != nil else { return }
        withAnimation(.snappy) { store.dismissReceipt() }
    }

    private var deleteBinding: Binding<Bool> {
        Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } })
    }

    private var cardTimerKey: String { "\(store.receipt?.id.uuidString ?? "-")-\(router.sheet == nil)" }

    private func rollOverAtMidnight() async {
        let cal = Calendar.current
        guard let next = cal.nextDate(after: Date(), matching: DateComponents(hour: 0, minute: 0, second: 2),
                                      matchingPolicy: .nextTime) else { return }
        try? await Task.sleep(for: .seconds(max(1, next.timeIntervalSinceNow)))
        if !Task.isCancelled { day = Clock.dayString() }
    }
}

/// Meal habits are a scan of the whole log, so they are rebuilt only when it changes.
@MainActor
private final class HabitsCache {
    private var key = ""
    private var value = MealHabits()

    func habits(_ ledger: Ledger, day: String) -> MealHabits {
        let k = "\(day)|\(ledger.events.count)|\(ledger.events.last?.id ?? "")"
        if k != key {
            value = MealHabits(ledger: ledger, today: day)
            key = k
        }
        return value
    }
}
