import Foundation

// Foundation-only pieces of the model layer. This folder is also compiled into the
// test target, so nothing here may touch SwiftUI, UIKit or the app's MainActor types.

/// Which kind of service a tier talks to.
enum ProviderKind: String, Codable, CaseIterable, Sendable, Identifiable {
    case onDevice, openAI, anthropic, off
    var id: String { rawValue }
    var title: String {
        switch self {
        case .onDevice: "On-device"
        case .openAI: "OpenAI-compatible"
        case .anthropic: "Anthropic"
        case .off: "Off"
        }
    }
}

/// Non-secret settings for one tier. The key lives in the Keychain.
struct TierConfig: Codable, Hashable, Sendable {
    var kind: ProviderKind
    var baseURL: String = ""
    var model: String = ""

    static let anthropicBaseURL = "https://api.anthropic.com"

    var trimmedBaseURL: String { baseURL.trimmingCharacters(in: .whitespacesAndNewlines) }
    var trimmedModel: String { model.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// Local servers (Ollama, LM Studio) run without a key.
    var isLocal: Bool {
        guard let host = URL(string: trimmedBaseURL)?.host()?.lowercased() else { return false }
        return host == "localhost" || host == "127.0.0.1" || host.hasSuffix(".local") || host.hasPrefix("192.168.")
            || host.hasPrefix("10.")
    }

    var needsKey: Bool {
        switch kind {
        case .openAI: !isLocal
        case .anthropic: true
        case .onDevice, .off: false
        }
    }

    /// "openrouter.ai · google/gemini-2.5-flash", the row name in the usage log.
    var usageKey: String {
        switch kind {
        case .onDevice: return "On-device"
        case .off: return "Off"
        case .anthropic:
            return "Anthropic · \(trimmedModel)"
        case .openAI:
            let host = URL(string: trimmedBaseURL)?.host() ?? trimmedBaseURL
            return "\(host.replacingOccurrences(of: "api.", with: "")) · \(trimmedModel)"
        }
    }
}

/// Known OpenAI-compatible services. Model names are only placeholder suggestions:
/// the field is free text and nothing here is a price list.
struct ServicePreset: Identifiable, Hashable, Sendable {
    var id: String
    var name: String
    var baseURL: String
    var fastModel: String
    var smartModel: String
    var note: String

    static let openAI: [ServicePreset] = [
        ServicePreset(id: "openrouter", name: "OpenRouter", baseURL: "https://openrouter.ai/api/v1",
                      fastModel: "google/gemini-2.5-flash-lite", smartModel: "anthropic/claude-sonnet-5.5",
                      note: "One key for most models"),
        ServicePreset(id: "groq", name: "Groq", baseURL: "https://api.groq.com/openai/v1",
                      fastModel: "llama-3.1-8b-instant", smartModel: "openai/gpt-oss-120b",
                      note: "Fast, has a free tier"),
        ServicePreset(id: "gemini", name: "Google Gemini", baseURL: "https://generativelanguage.googleapis.com/v1beta/openai",
                      fastModel: "gemini-2.5-flash-lite", smartModel: "gemini-2.5-flash",
                      note: "Has a free tier"),
        ServicePreset(id: "deepseek", name: "DeepSeek", baseURL: "https://api.deepseek.com/v1",
                      fastModel: "deepseek-chat", smartModel: "deepseek-chat", note: "Text only"),
        ServicePreset(id: "openai", name: "OpenAI", baseURL: "https://api.openai.com/v1",
                      fastModel: "gpt-5-nano", smartModel: "gpt-5-mini", note: ""),
        ServicePreset(id: "ollama", name: "Ollama", baseURL: "http://localhost:11434/v1",
                      fastModel: "llama3.2", smartModel: "qwen2.5vl", note: "Replace localhost with your Mac's address"),
    ]

    static let anthropicFast = "claude-haiku-5-5"
    static let anthropicSmart = "claude-sonnet-5-5"

    static func matching(_ baseURL: String) -> ServicePreset? {
        let u = baseURL.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return openAI.first { u.hasPrefix($0.baseURL.lowercased()) }
    }
}

// MARK: - usage

struct UsageCounts: Codable, Hashable, Sendable {
    var requests = 0
    var input = 0
    var output = 0
    var cached = 0

    static func + (a: UsageCounts, b: UsageCounts) -> UsageCounts {
        UsageCounts(requests: a.requests + b.requests, input: a.input + b.input, output: a.output + b.output,
                    cached: a.cached + b.cached)
    }
}

/// Requests and tokens per provider per day, from each API's own usage fields. Shown
/// in Models settings so the cost of a day is visible without a price table.
struct UsageLog: Codable, Hashable, Sendable {
    /// day -> usage key -> counts.
    var days: [String: [String: UsageCounts]] = [:]

    mutating func record(_ key: String, _ usage: ModelUsage, day: String = Clock.dayString()) {
        var c = days[day]?[key] ?? UsageCounts()
        c.requests += 1
        c.input += usage.input
        c.output += usage.output
        c.cached += usage.cached
        days[day, default: [:]][key] = c
        trim(keeping: 60, today: day)
    }

    func on(_ day: String) -> [(key: String, counts: UsageCounts)] {
        (days[day] ?? [:]).sorted { $0.key < $1.key }.map { ($0.key, $0.value) }
    }

    func total(lastDays n: Int, today: String = Clock.dayString()) -> UsageCounts {
        let start = Clock.addDays(today, -(n - 1))
        return days.filter { $0.key >= start && $0.key <= today }.values
            .flatMap(\.values).reduce(UsageCounts(), +)
    }

    private mutating func trim(keeping n: Int, today: String) {
        let cutoff = Clock.addDays(today, -n)
        days = days.filter { $0.key > cutoff }
    }

    /// 8200 -> "8.2k".
    static func tokens(_ n: Int) -> String {
        switch n {
        case ..<1000: return "\(n)"
        case ..<1_000_000: return Format.trim(Double(n) / 1000, digits: n < 10_000 ? 1 : 0) + "k"
        default: return Format.trim(Double(n) / 1_000_000, digits: 1) + "M"
        }
    }

    static func summary(_ c: UsageCounts) -> String {
        let req = c.requests == 1 ? "1 request" : "\(c.requests) requests"
        guard c.input + c.output > 0 else { return req }
        return "\(req) · \(tokens(c.input)) in · \(tokens(c.output)) out"
    }
}
