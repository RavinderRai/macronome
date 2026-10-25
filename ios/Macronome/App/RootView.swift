import SwiftUI

struct RootView: View {
    @Environment(FoodStore.self) private var store
    @Environment(Router.self) private var router
    @AppStorage("onboarded") private var onboarded = false

    var body: some View {
        @Bindable var router = router
        Group {
            if !onboarded && store.isEmpty {
                NavigationStack(path: $router.path) {
                    WelcomeView(onFinish: { onboarded = true })
                        .navigationDestination(for: Route.self, destination: destination)
                }
            } else {
                NavigationStack(path: $router.path) {
                    tabRoot
                        .navigationDestination(for: Route.self, destination: destination)
                }
            }
        }
        .sheet(item: $router.sheet) { sheet in
            switch sheet {
            case .chat(let prompt): ChatSheet(initialPrompt: prompt)
            case .listening: ListeningView()
            case .editGroup(let id): LoggedEditView(groupID: id)
            }
        }
        .fullScreenCover(item: $router.cover) { cover in
            switch cover {
            case .labelScan: LabelScanView()
            case .platePhoto: PlatePhotoView()
            case .pantryScan: PantryScanView()
            }
        }
    }

    @ViewBuilder private var tabRoot: some View {
        switch router.tab {
        case .today: TodayView()
        case .foods: FoodsView()
        case .history: HistoryView()
        }
    }

    @ViewBuilder private func destination(_ route: Route) -> some View {
        switch route {
        case .entry(let id): EntryDetailView(groupID: id)
        case .food(let id): FoodDetailView(foodID: id)
        case .meal(let id): MealDetailView(mealID: id)
        case .newMeal: MealDetailView(mealID: nil)
        case .day(let day): DayView(day: day)
        case .settings: SettingsView()
        case .memory: MemoryView()
        case .targets(let onboarding): TargetsView(onboarding: onboarding)
        case .aiSettings: AISettingsView()
        case .newFood(let draft): NewFoodView(draft: draft)
        case .pantryReview(let drafts): PantryReviewView(drafts: drafts)
        }
    }
}

/// "Today  Foods  History ··· (R)".
struct TopNav: View {
    @Environment(Router.self) private var router
    @AppStorage("initial") private var initial = "R"

    var body: some View {
        HStack(spacing: 20) {
            ForEach(Tab.allCases) { tab in
                Button(tab.title) { router.show(tab) }
                    .font(.system(size: 17, weight: router.tab == tab ? .semibold : .medium))
                    .foregroundStyle(router.tab == tab ? Theme.text : Theme.text3)
                    .padding(.vertical, 12)
                    .accessibilityAddTraits(router.tab == tab ? .isSelected : [])
            }
            Spacer()
            Button { router.push(.settings) } label: {
                Text(initial.prefix(1))
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(Theme.text))
                    .foregroundStyle(Theme.graphite)
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("Settings")
        }
        .padding(.leading, 20).padding(.trailing, 10)
        .frame(height: 56)
    }
}
