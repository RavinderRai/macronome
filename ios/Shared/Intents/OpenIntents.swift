import AppIntents
import Foundation

/// Where the app should go when an intent opens it. The intent may run before the
/// UI exists, so the route is parked in shared defaults and the app picks it up.
enum PendingRoute {
    static let key = "pendingRoute"
    nonisolated(unsafe) static var defaults: UserDefaults {
        FoodStore.appGroupID.flatMap { UserDefaults(suiteName: $0) } ?? .standard
    }
    static func set(_ host: String) { defaults.set(host, forKey: key) }
    static func take() -> URL? {
        guard let host = defaults.string(forKey: key) else { return nil }
        defaults.removeObject(forKey: key)
        return URL(string: "macronome://\(host)")
    }
}

/// Opens the app straight into the listening panel. Used by the widget mic button,
/// the Control Center control and the Action Button.
struct OpenListeningIntent: AppIntent {
    static let title: LocalizedStringResource = "Log by voice"
    static let description = IntentDescription("Opens Macronome listening, ready to log what you ate.")
    static let openAppWhenRun = true

    func perform() async throws -> some IntentResult {
        PendingRoute.set("listen")
        return .result()
    }
}

struct OpenCameraIntent: AppIntent {
    static let title: LocalizedStringResource = "Scan a label"
    static let description = IntentDescription("Opens Macronome's label camera.")
    static let openAppWhenRun = true

    func perform() async throws -> some IntentResult {
        PendingRoute.set("camera")
        return .result()
    }
}
