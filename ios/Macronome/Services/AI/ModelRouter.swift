import Foundation
import Observation

/// Every model call in the app goes through here, so cost routing lives in one place.
///
/// Two tiers:
/// - fast: parsing a log, short answers. Free on-device model where available, else a
///   cheap cloud model.
/// - smart: the chat, plate photos, reading a label with vision.
///
/// Non-secret settings live in UserDefaults, keys in the Keychain, and a small usage
/// log (requests and tokens per provider per day) in UserDefaults.
@MainActor
@Observable
final class ModelRouter {
    enum Tier: String, Codable, CaseIterable, Sendable { case fast, smart }

    private(set) var fast: TierConfig
    private(set) var smart: TierConfig
    private(set) var usage: UsageLog
    /// Keys read once from the Keychain; the Keychain stays the store of record.
    private var keys: [Tier: String] = [:]

    @ObservationIgnored private let defaults: UserDefaults
    private static let configKey = "models.config.v1"
    private static let usageKey = "models.usage.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let stored = defaults.data(forKey: Self.configKey).flatMap { try? JSONDecoder().decode([String: TierConfig].self, from: $0) }
        fast = stored?[Tier.fast.rawValue] ?? TierConfig(kind: .onDevice)
        smart = stored?[Tier.smart.rawValue] ?? TierConfig(kind: .off)
        usage = defaults.data(forKey: Self.usageKey).flatMap { try? JSONDecoder().decode(UsageLog.self, from: $0) } ?? UsageLog()
        for t in Tier.allCases { keys[t] = Keychain.read(t.rawValue) }
    }

    // MARK: settings

    func config(_ tier: Tier) -> TierConfig { tier == .fast ? fast : smart }

    func update(_ tier: Tier, _ config: TierConfig) {
        if tier == .fast { fast = config } else { smart = config }
        let all = [Tier.fast.rawValue: fast, Tier.smart.rawValue: smart]
        if let data = try? JSONEncoder().encode(all) { defaults.set(data, forKey: Self.configKey) }
    }

    func hasOwnKey(_ tier: Tier) -> Bool { !(keys[tier] ?? "").isEmpty }

    /// The tier's key, or the other tier's when both point at the same service, so
    /// one OpenRouter or Anthropic key covers both.
    func apiKey(_ tier: Tier) -> String? {
        if let k = keys[tier], !k.isEmpty { return k }
        let other: Tier = tier == .fast ? .smart : .fast
        return sharesKey(tier, with: other) ? keys[other].flatMap { $0.isEmpty ? nil : $0 } : nil
    }

    func sharesKey(_ tier: Tier, with other: Tier) -> Bool {
        let a = config(tier), b = config(other)
        guard a.kind == b.kind, a.kind == .openAI || a.kind == .anthropic else { return false }
        if a.kind == .anthropic { return true }
        return URL(string: a.trimmedBaseURL)?.host() == URL(string: b.trimmedBaseURL)?.host() && !a.trimmedBaseURL.isEmpty
    }

    func setAPIKey(_ key: String?, for tier: Tier) {
        let k = key?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if k.isEmpty { Keychain.delete(tier.rawValue) } else { Keychain.write(k, for: tier.rawValue) }
        keys[tier] = k
    }

    var onDeviceStatus: OnDeviceModel.Status { OnDeviceModel.status }

    // MARK: routing

    /// True when the given tier has a usable provider.
    func isConfigured(_ tier: Tier) -> Bool { provider(tier) != nil }

    /// The provider behind a tier, or nil when it is off or incomplete.
    func provider(_ tier: Tier) -> (any ModelProvider)? {
        let c = config(tier)
        switch c.kind {
        case .off: return nil
        case .onDevice: return OnDeviceModel.isAvailable ? OnDeviceProvider() : nil
        case .openAI:
            guard !c.trimmedBaseURL.isEmpty, !c.trimmedModel.isEmpty else { return nil }
            let key = apiKey(tier)
            if c.needsKey && key == nil { return nil }
            return OpenAICompatibleProvider(baseURL: c.trimmedBaseURL, model: c.trimmedModel, apiKey: key)
        case .anthropic:
            guard !c.trimmedModel.isEmpty, let key = apiKey(tier) else { return nil }
            return AnthropicProvider(baseURL: c.trimmedBaseURL, model: c.trimmedModel, apiKey: key)
        }
    }

    /// The chat runs on smart, or on fast when that is all there is.
    var chatTier: Tier? { isConfigured(.smart) ? .smart : isConfigured(.fast) ? .fast : nil }

    /// Smart if it can take images, else fast if that can.
    private func visionProvider() throws -> any ModelProvider {
        for tier in [Tier.smart, .fast] {
            if let p = provider(tier), p.acceptsImages { return p }
        }
        if isConfigured(.smart) || isConfigured(.fast) {
            throw ModelError.unsupported("The on-device model can't read photos. Add a smart model in Settings → Models.")
        }
        throw ModelError.notConfigured(.smart)
    }

    func record(_ key: String, _ u: ModelUsage) {
        usage.record(key, u)
        if let data = try? JSONEncoder().encode(usage) { defaults.set(data, forKey: Self.usageKey) }
    }

    private func run(_ provider: any ModelProvider, _ request: ModelRequest) async throws -> ModelReply {
        do {
            let reply = try await provider.complete(request)
            record(provider.usageKey, reply.usage)
            return reply
        } catch let e as ProviderError {
            throw ModelError(e)
        }
    }

    /// A one-line check for the settings screen. Costs a handful of tokens.
    func test(_ tier: Tier) async -> (ok: Bool, message: String) {
        guard let p = provider(tier) else {
            let c = config(tier)
            switch c.kind {
            case .off: return (false, "Off")
            case .onDevice: return (false, OnDeviceModel.statusText)
            default:
                if c.trimmedModel.isEmpty { return (false, "Add a model name.") }
                if c.kind == .openAI && c.trimmedBaseURL.isEmpty { return (false, "Add a base URL.") }
                return (false, "Add an API key.")
            }
        }
        let start = Date()
        let req = ModelRequest(system: ["Reply with the single word: ok"], messages: [ModelMessage(role: .user, text: "ping")],
                               maxTokens: 64, timeout: 30)
        do {
            _ = try await run(p, req)
            return (true, "Works · answered in \(Format.trim(Date().timeIntervalSince(start), digits: 1)) s")
        } catch {
            return (false, error.localizedDescription)
        }
    }

    // MARK: tasks

    /// An interpreter for logs the local parser could not resolve, or nil when no
    /// fast-tier model is available.
    func interpreter() -> LogInterpreter? {
        guard let p = provider(.fast) else { return nil }
        let record: @Sendable (String, ModelUsage) async -> Void = { [weak self] key, u in
            await self?.record(key, u)
        }
        if p is OnDeviceProvider { return AILogInterpreter(backend: .onDevice, record: record) }
        return AILogInterpreter(backend: .cloud(p), record: record)
    }

    /// One chat turn. The reply's options carry components; macros are recomputed
    /// locally from the ledger, never taken from the model.
    func reply(to history: [ChatMessage], ledger: Ledger) async throws -> ChatMessage {
        guard let tier = chatTier, let p = provider(tier) else { throw ModelError.notConfigured(.smart) }
        let compact = p is OnDeviceProvider
        let turns = history.filter { $0.role != .system }.suffix(compact ? 4 : 14).map(Self.turn)
        let req = ModelRequest(system: ChatPrompt.system(ledger: ledger, compact: compact), messages: Array(turns),
                               jsonMode: true, maxTokens: 4000, timeout: 90)
        let reply = try await run(p, req)
        let text = reply.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw ModelError.badResponse("the reply was empty") }
        return ChatReplyParser.parse(text, ledger: ledger)
    }

    /// Past assistant turns are sent with their options in words, so a follow-up like
    /// "make the second one bigger" has something to refer to.
    private static func turn(_ m: ChatMessage) -> ModelMessage {
        guard m.role == .assistant, !m.options.isEmpty else {
            return ModelMessage(role: m.role == .user ? .user : .assistant, text: m.text)
        }
        let opts = m.options.enumerated().map { i, o in
            let comps = o.components.map { "\(Format.trim($0.qty, digits: 2)) \($0.unit) [\($0.foodID)]" }.joined(separator: " + ")
            return "\(i + 1). \(o.title)\(o.mealID.map { " (meal_id \($0))" } ?? ""): \(comps)"
        }.joined(separator: "\n")
        return ModelMessage(role: .assistant, text: m.text + "\nOptions offered:\n" + opts)
    }

    /// Estimate a plated meal from a photo. Logged as a one-off, never added to foods.
    func estimatePlate(imageData: Data, note: String?, ledger: Ledger) async throws -> PlateEstimate {
        let p = try visionProvider()
        let reply = try await run(p, VisionTasks.plateRequest(image: imageData, note: note, ledger: ledger))
        return try VisionTasks.parsePlate(reply.text)
    }

    /// Read a nutrition label with a vision model, when on-device OCR was not enough.
    func readLabel(imageData: Data) async throws -> FoodDraft {
        let p = try visionProvider()
        let reply = try await run(p, VisionTasks.labelRequest(image: imageData))
        return try VisionTasks.parseLabel(reply.text)
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
