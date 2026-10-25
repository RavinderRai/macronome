import SwiftUI

@main
struct MacronomeApp: App {
    @State private var store = FoodStore()
    @State private var router = Router()
    @State private var services = AppServices()
    @Environment(\.scenePhase) private var scenePhase

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
                .onChange(of: scenePhase) { _, phase in
                    guard phase == .active else { return }
                    // Logs written by Siri or another process while we were away.
                    store.reload()
                    if let url = PendingRoute.take() { router.open(url) }
                }
        }
    }
}
