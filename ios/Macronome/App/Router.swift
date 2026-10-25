import SwiftUI

enum Tab: String, CaseIterable, Identifiable {
    case today, foods, history
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

/// Pushed screens. Each case maps to one design artboard.
enum Route: Hashable {
    case entry(String)          // EntryDetail: a group id or entry id
    case food(String)           // FoodDetail
    case meal(String)           // MealDetail
    case newMeal
    case day(String)            // a past day from History
    case settings
    case memory
    case targets(onboarding: Bool)
    case aiSettings
    case newFood(FoodDraft)     // NewFood form, often prefilled from a label
    case pantryReview([FoodDraft])
    case widgets                // preview of the home-screen widgets
}

/// Modal screens.
enum SheetRoute: Identifiable, Hashable {
    case chat(prompt: String?)  // ChatSheet
    case listening              // Listening
    case editGroup(String)      // LoggedEdit
    var id: String {
        switch self {
        case .chat(let p): "chat-\(p ?? "")"
        case .listening: "listening"
        case .editGroup(let g): "edit-\(g)"
        }
    }
}

enum CoverRoute: Identifiable, Hashable {
    case labelScan              // LabelScan camera
    case platePhoto             // PlatePhoto
    case pantryScan             // onboarding PantryScan
    var id: Self { self }
}

@MainActor
@Observable
final class Router {
    var tab: Tab = .today
    var path = NavigationPath()
    var sheet: SheetRoute?
    var cover: CoverRoute?

    func push(_ r: Route) { path.append(r) }
    func popToRoot() { path = NavigationPath() }

    func show(_ tab: Tab) {
        self.tab = tab
        popToRoot()
    }

    /// macronome://listen, macronome://camera, macronome://today from the widget.
    func open(_ url: URL) {
        guard url.scheme == "macronome" else { return }
        sheet = nil
        cover = nil
        switch url.host() {
        case "listen": show(.today); sheet = .listening
        case "camera": show(.today); cover = .labelScan
        case "chat": show(.today); sheet = .chat(prompt: nil)
        case "foods": show(.foods)
        case "history": show(.history)
        case "settings": show(.today); push(.settings)
        case "widgets": show(.today); push(.widgets)
        default: show(.today)
        }
    }
}
