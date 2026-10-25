import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Apple's on-device model (iOS 26, Apple Intelligence). Free, private, text only,
/// with a small context window, so it gets the fast tier and a compact prompt.
enum OnDeviceModel {
    enum Status: Equatable {
        case available, notEligible, intelligenceOff, notReady, unsupported
    }

    static var status: Status {
        #if canImport(FoundationModels)
        switch SystemLanguageModel.default.availability {
        case .available: return .available
        case .unavailable(.deviceNotEligible): return .notEligible
        case .unavailable(.appleIntelligenceNotEnabled): return .intelligenceOff
        case .unavailable(.modelNotReady): return .notReady
        case .unavailable: return .unsupported
        }
        #else
        return .unsupported
        #endif
    }

    static var isAvailable: Bool { status == .available }

    static var statusText: String {
        switch status {
        case .available: "Ready"
        case .notEligible: "Not available on this iPhone"
        case .intelligenceOff: "Apple Intelligence is off"
        case .notReady: "Still downloading"
        case .unsupported: "Not available"
        }
    }
}

struct OnDeviceProvider: ModelProvider {
    var usageKey: String { "On-device" }
    var acceptsImages: Bool { false }

    func complete(_ r: ModelRequest) async throws -> ModelReply {
        guard r.images.isEmpty else { throw ProviderError.unsupported("The on-device model can't read photos.") }
        #if canImport(FoundationModels)
        guard OnDeviceModel.isAvailable else { throw ProviderError.unsupported("The on-device model is \(OnDeviceModel.statusText.lowercased()).") }
        let turns = normalizedTurns(r.messages)
        // Earlier turns go into the instructions as a transcript; the session itself
        // is one-shot so nothing is kept between calls.
        var instructions = r.system.joined(separator: "\n\n")
        if turns.count > 1 {
            let past = turns.dropLast().map { "\($0.role == .user ? "Ravi" : "You"): \($0.text)" }.joined(separator: "\n")
            instructions += "\n\nConversation so far:\n" + past
        }
        let session = LanguageModelSession(instructions: instructions)
        do {
            let response = try await session.respond(to: turns.last?.text ?? "")
            return ModelReply(text: response.content, usage: ModelUsage())
        } catch {
            throw ProviderError.unsupported(Self.describe(error))
        }
        #else
        throw ProviderError.unsupported("The on-device model needs iOS 26.")
        #endif
    }

    static func describe(_ error: Error) -> String {
        #if canImport(FoundationModels)
        if let e = error as? LanguageModelSession.GenerationError {
            switch e {
            case .exceededContextWindowSize: return "Too much for the on-device model. Add a smart model in Settings → Models."
            case .guardrailViolation: return "The on-device model declined that."
            default: break
            }
        }
        #endif
        return "The on-device model failed: \(error.localizedDescription)"
    }
}

#if canImport(FoundationModels)
/// Guided generation for the interpreter, so the small model always returns the shape.
@Generable
struct OnDeviceLogItems {
    @Guide(description: "One entry per food or meal mentioned")
    var items: [OnDeviceLogItem]
}

@Generable
struct OnDeviceLogItem {
    @Guide(description: "The words that describe this item")
    var phrase: String
    @Guide(description: "id copied from the food list, when the food is in it")
    var foodID: String?
    @Guide(description: "meal_id copied from the usual meals list, when a usual meal is named")
    var mealID: String?
    var qty: Double?
    @Guide(description: "g, ml, serving, or the food's unit from the list")
    var unit: String?
    @Guide(description: "Short name, for foods not in the list")
    var label: String?
    @Guide(description: "Estimated calories, only for foods not in the list")
    var kcal: Double?
    var protein: Double?
    var carbs: Double?
    var fat: Double?

    var interpreted: InterpretedItem {
        InterpretedItem(phrase: phrase, foodID: foodID, mealID: mealID, qty: qty, unit: unit, label: label, kcal: kcal,
                        protein: protein, carbs: carbs, fat: fat, fiber: nil)
    }
}

enum OnDeviceInterpreter {
    static func items(_ text: String, ledger: Ledger) async throws -> [InterpretedItem] {
        let rules = """
        You turn what Ravi says he ate into log items. Match foods to the list by id and usual meals by \
        meal_id. Copy ids exactly; never invent one. Foods not in the list get a label and estimated macros.
        """
        let session = LanguageModelSession(instructions: rules + "\n\n" + InterpreterPrompt.library(ledger, limit: 80))
        do {
            let r = try await session.respond(to: text, generating: OnDeviceLogItems.self)
            return r.content.items.map(\.interpreted)
        } catch {
            throw ProviderError.unsupported(OnDeviceProvider.describe(error))
        }
    }
}
#endif
