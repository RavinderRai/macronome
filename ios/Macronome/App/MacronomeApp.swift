import SwiftUI

@main
struct MacronomeApp: App {
    @State private var store = FoodStore()
    @State private var router = Router()
    @State private var services = AppServices()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .environment(router)
                .environment(services)
                .preferredColorScheme(.dark)
                .tint(Theme.amber)
                .onOpenURL { router.open($0) }
                .task { store.seedIfNeeded() }
        }
    }
}
