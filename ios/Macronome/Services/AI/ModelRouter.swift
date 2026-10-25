import Foundation
import Observation

/// Every model call in the app goes through here, so cost routing lives in one place.
///
/// Two tiers:
/// - fast: parsing a log, short answers. Free on-device model where available, else a
///   cheap cloud model.
/// - smart: the chat, plate photos, reading a label with vision.
///
/// API is fixed; the implementation is filled in by the model layer.
@MainActor
@Observable
final class ModelRouter {
    enum Tier: String, Codable, CaseIterable, Sendable { case fast, smart }

    /// True when the given tier has a usable provider.
    func isConfigured(_ tier: Tier) -> Bool { false }

    /// An interpreter for logs the local parser could not resolve, or nil when no
    /// fast-tier model is available.
    func interpreter() -> LogInterpreter? { nil }

    /// One chat turn. The reply's options carry components; macros are recomputed
    /// locally from the ledger, never taken from the model.
    func reply(to history: [ChatMessage], ledger: Ledger) async throws -> ChatMessage {
        throw ModelError.notConfigured(.smart)
    }

    /// Estimate a plated meal from a photo. Logged as a one-off, never added to foods.
    func estimatePlate(imageData: Data, note: String?, ledger: Ledger) async throws -> PlateEstimate {
        throw ModelError.notConfigured(.smart)
    }

    /// Read a nutrition label with a vision model, when on-device OCR was not enough.
    func readLabel(imageData: Data) async throws -> FoodDraft {
        throw ModelError.notConfigured(.smart)
    }
}

struct PlateEstimate: Hashable, Sendable {
    struct Item: Hashable, Sendable, Identifiable {
        var id = UUID()
        var label: String
        var grams: Double?
        var macros: Macros
    }
    var title: String
    var items: [Item]
    /// "low" | "medium" | "high".
    var confidence: String
    var note: String?
    var total: Macros { items.reduce(.zero) { $0 + $1.macros } }
}

enum ModelError: LocalizedError, Equatable {
    case notConfigured(ModelRouter.Tier)
    case unsupported(String)
    case badResponse(String)
    case http(Int, String)

    var errorDescription: String? {
        switch self {
        case .notConfigured(let t): "No \(t.rawValue) model is set up. Add one in Settings → Models."
        case .unsupported(let s): s
        case .badResponse(let s): "The model's answer could not be read: \(s)"
        case .http(let code, let body): "The model service returned \(code). \(body)"
        }
    }
}
