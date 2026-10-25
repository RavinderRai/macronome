import Foundation

struct ModelMessage: Hashable, Sendable {
    enum Role: String, Sendable { case user, assistant }
    var role: Role
    var text: String
}

struct ModelRequest: Sendable {
    /// System prompt in parts, most stable first. Anthropic caches the first part.
    var system: [String]
    var messages: [ModelMessage]
    /// JPEG images attached to the last user message.
    var images: [Data] = []
    /// Ask for a JSON object (OpenAI-compatible `response_format`).
    var jsonMode = false
    var maxTokens = 1500
    /// Anthropic `output_config.effort`; dropped automatically for models that reject it.
    var effort: String? = "low"
    var timeout: TimeInterval = 60
}

struct ModelUsage: Codable, Hashable, Sendable {
    var input = 0
    var output = 0
    /// Part of `input` served from a prompt cache.
    var cached = 0
}

struct ModelReply: Sendable {
    var text: String
    var usage: ModelUsage
}

/// One service that turns a request into text.
protocol ModelProvider: Sendable {
    var usageKey: String { get }
    var acceptsImages: Bool { get }
    func complete(_ request: ModelRequest) async throws -> ModelReply
}

enum ProviderError: LocalizedError, Equatable {
    case unsupported(String)
    case badResponse(String)
    case http(Int, String)
    case network(String)

    var errorDescription: String? {
        switch self {
        case .unsupported(let s), .network(let s): s
        case .badResponse(let s): "The model's answer could not be read: \(s)"
        case .http(let code, let s): "The model service returned \(code). \(s)"
        }
    }

    /// One line a person can act on, for 401/404/429 and the provider's own message.
    static func friendly(status: Int, body: Data) -> ProviderError {
        let message = providerMessage(body)
        let hint: String
        switch status {
        case 401, 403: hint = "The key was refused. Check the API key."
        case 404: hint = "Not found. Check the model name and base URL."
        case 429: hint = "Rate limited or out of credit. Try again shortly, or check the account's balance."
        case 400 where (message ?? "").lowercased().contains("model"): hint = "The service did not accept the model name."
        case 500...599: hint = "The service is having trouble. Try again in a minute."
        default: hint = ""
        }
        let parts = [hint, message.map { String($0.prefix(180)) }].compactMap { $0 }.filter { !$0.isEmpty }
        return .http(status, parts.joined(separator: " "))
    }

    /// `{"error": {"message": ...}}`, `{"error": "..."}` or `[{"error": {...}}]` (Gemini).
    static func providerMessage(_ body: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: body) else {
            let s = String(data: body, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            return s?.isEmpty == false ? s : nil
        }
        let obj = (json as? [String: Any]) ?? (json as? [[String: Any]])?.first
        if let e = obj?["error"] as? [String: Any], let m = e["message"] as? String { return m }
        if let e = obj?["error"] as? String { return e }
        if let m = obj?["message"] as? String { return m }
        return nil
    }
}

// MARK: - HTTP

enum HTTP {
    static let session: URLSession = {
        let c = URLSessionConfiguration.ephemeral
        c.timeoutIntervalForRequest = 60
        c.timeoutIntervalForResource = 180
        c.waitsForConnectivity = false
        return URLSession(configuration: c)
    }()

    static func post(_ url: URL, headers: [String: String], body: [String: Any], timeout: TimeInterval) async throws -> (Int, Data) {
        var req = URLRequest(url: url, timeoutInterval: timeout)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        for (k, v) in headers { req.setValue(v, forHTTPHeaderField: k) }
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        do {
            let (data, resp) = try await session.data(for: req)
            return ((resp as? HTTPURLResponse)?.statusCode ?? 0, data)
        } catch let e as URLError {
            switch e.code {
            case .timedOut: throw ProviderError.network("The model took too long to answer.")
            case .notConnectedToInternet, .networkConnectionLost: throw ProviderError.network("No connection.")
            case .cannotFindHost, .cannotConnectToHost: throw ProviderError.network("Could not reach \(url.host() ?? "the service"). Check the base URL.")
            case .appTransportSecurityRequiresSecureConnection: throw ProviderError.network("Plain http is blocked for this address. Use https.")
            default: throw ProviderError.network(e.localizedDescription)
            }
        }
    }

    static func endpoint(_ base: String, appending path: String) -> URL? {
        var b = base.trimmingCharacters(in: .whitespacesAndNewlines)
        while b.hasSuffix("/") { b.removeLast() }
        guard !b.isEmpty else { return nil }
        return URL(string: b + path)
    }
}

/// Merge consecutive turns of the same role and drop leading assistant turns, which
/// Anthropic rejects and other services handle poorly.
func normalizedTurns(_ messages: [ModelMessage]) -> [ModelMessage] {
    var out: [ModelMessage] = []
    for m in messages where !m.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        if out.isEmpty && m.role == .assistant { continue }
        if let last = out.last, last.role == m.role {
            out[out.count - 1].text += "\n\n" + m.text
        } else {
            out.append(m)
        }
    }
    return out
}

// MARK: - OpenAI-compatible

/// Any `/chat/completions` endpoint: OpenRouter, Groq, Gemini, DeepSeek, OpenAI,
/// Ollama, LM Studio, or a self-hosted relay.
struct OpenAICompatibleProvider: ModelProvider {
    var baseURL: String
    var model: String
    var apiKey: String?
    var acceptsImages: Bool { true }
    var usageKey: String { TierConfig(kind: .openAI, baseURL: baseURL, model: model).usageKey }

    struct Options: Equatable {
        var json: Bool
        var maxKey = "max_tokens"
    }

    func body(_ r: ModelRequest, options: Options) -> [String: Any] {
        var messages: [[String: Any]] = []
        let system = r.system.joined(separator: "\n\n")
        if !system.isEmpty { messages.append(["role": "system", "content": system]) }
        let turns = normalizedTurns(r.messages)
        for (i, m) in turns.enumerated() {
            if i == turns.count - 1, m.role == .user, !r.images.isEmpty {
                var parts: [[String: Any]] = [["type": "text", "text": m.text]]
                for img in r.images {
                    parts.append(["type": "image_url",
                                  "image_url": ["url": "data:image/jpeg;base64," + img.base64EncodedString()]])
                }
                messages.append(["role": m.role.rawValue, "content": parts])
            } else {
                messages.append(["role": m.role.rawValue, "content": m.text])
            }
        }
        var body: [String: Any] = ["model": model, "messages": messages, options.maxKey: r.maxTokens]
        if options.json { body["response_format"] = ["type": "json_object"] }
        return body
    }

    func complete(_ r: ModelRequest) async throws -> ModelReply {
        guard let url = HTTP.endpoint(baseURL, appending: "/chat/completions") else {
            throw ProviderError.unsupported("Add a base URL in Settings → Models.")
        }
        var headers: [String: String] = [:]
        if let apiKey, !apiKey.isEmpty { headers["Authorization"] = "Bearer \(apiKey)" }
        if url.host()?.contains("openrouter") == true { headers["X-Title"] = "Macronome" }

        // Not every compatible server takes response_format or max_tokens; on a 400
        // that names the field, retry once without it.
        var options = Options(json: r.jsonMode)
        for attempt in 0..<3 {
            let (status, data) = try await HTTP.post(url, headers: headers, body: body(r, options: options), timeout: r.timeout)
            if status == 200 { return try Self.parse(data) }
            let msg = (ProviderError.providerMessage(data) ?? "").lowercased()
            if status == 400, attempt < 2 {
                if options.json, msg.contains("response_format") || msg.contains("json") {
                    options.json = false
                    continue
                }
                if options.maxKey == "max_tokens", msg.contains("max_tokens") || msg.contains("max_completion_tokens") {
                    options.maxKey = "max_completion_tokens"
                    continue
                }
            }
            throw ProviderError.friendly(status: status, body: data)
        }
        throw ProviderError.badResponse("no answer")
    }

    static func parse(_ data: Data) throws -> ModelReply {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choice = (obj["choices"] as? [[String: Any]])?.first,
              let message = choice["message"] as? [String: Any] else {
            throw ProviderError.badResponse("no choices in the reply")
        }
        var text = ""
        if let s = message["content"] as? String {
            text = s
        } else if let parts = message["content"] as? [[String: Any]] {
            text = parts.compactMap { $0["text"] as? String }.joined()
        }
        if text.isEmpty, let refusal = message["refusal"] as? String { throw ProviderError.unsupported(refusal) }
        var usage = ModelUsage()
        if let u = obj["usage"] as? [String: Any] {
            usage.input = u["prompt_tokens"] as? Int ?? 0
            usage.output = u["completion_tokens"] as? Int ?? 0
            usage.cached = (u["prompt_tokens_details"] as? [String: Any])?["cached_tokens"] as? Int ?? 0
        }
        return ModelReply(text: text, usage: usage)
    }
}

// MARK: - Anthropic

/// Anthropic's Messages API with an API key. (A Claude Pro/Max login cannot be used
/// from a third-party app, so there is deliberately no OAuth path.)
struct AnthropicProvider: ModelProvider {
    static let version = "2026-10-21"

    var baseURL: String = TierConfig.anthropicBaseURL
    var model: String
    var apiKey: String
    var acceptsImages: Bool { true }
    var usageKey: String { TierConfig(kind: .anthropic, baseURL: baseURL, model: model).usageKey }

    var url: URL? {
        let base = baseURL.isEmpty ? TierConfig.anthropicBaseURL : baseURL
        return HTTP.endpoint(base, appending: base.trimmingCharacters(in: CharacterSet(charactersIn: "/")).hasSuffix("/v1") ? "/messages" : "/v1/messages")
    }

    func body(_ r: ModelRequest, effort: Bool) -> [String: Any] {
        // The stable part of the system prompt (rules, library, meals) is cached so
        // a chat's follow-up turns are billed at the cache rate.
        var system: [[String: Any]] = []
        for (i, part) in r.system.enumerated() where !part.isEmpty {
            var block: [String: Any] = ["type": "text", "text": part]
            if i == 0 && r.system.count > 1 { block["cache_control"] = ["type": "ephemeral"] }
            system.append(block)
        }
        let turns = normalizedTurns(r.messages)
        let messages: [[String: Any]] = turns.enumerated().map { i, m in
            var content: [[String: Any]] = []
            if i == turns.count - 1, m.role == .user {
                for img in r.images {
                    content.append(["type": "image", "source": ["type": "base64", "media_type": "image/jpeg",
                                                                "data": img.base64EncodedString()]])
                }
            }
            content.append(["type": "text", "text": m.text])
            return ["role": m.role.rawValue, "content": content]
        }
        var body: [String: Any] = ["model": model, "max_tokens": r.maxTokens, "messages": messages]
        if !system.isEmpty { body["system"] = system }
        if effort, let e = r.effort { body["output_config"] = ["effort": e] }
        return body
    }

    func complete(_ r: ModelRequest) async throws -> ModelReply {
        guard let url else { throw ProviderError.unsupported("The Anthropic base URL is not valid.") }
        let headers = ["x-api-key": apiKey, "anthropic-version": Self.version]
        var effort = r.effort != nil
        for attempt in 0..<2 {
            let (status, data) = try await HTTP.post(url, headers: headers, body: body(r, effort: effort), timeout: r.timeout)
            if status == 200 { return try Self.parse(data) }
            let msg = (ProviderError.providerMessage(data) ?? "").lowercased()
            // Older models do not take effort.
            if status == 400, attempt == 0, effort, msg.contains("effort") || msg.contains("output_config") {
                effort = false
                continue
            }
            throw ProviderError.friendly(status: status, body: data)
        }
        throw ProviderError.badResponse("no answer")
    }

    static func parse(_ data: Data) throws -> ModelReply {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = obj["content"] as? [[String: Any]] else {
            throw ProviderError.badResponse("no content in the reply")
        }
        if obj["stop_reason"] as? String == "refusal" {
            throw ProviderError.unsupported("The model declined to answer that.")
        }
        // Thinking blocks come back too; only text blocks are the answer.
        let text = content.filter { $0["type"] as? String == "text" }.compactMap { $0["text"] as? String }.joined()
        var usage = ModelUsage()
        if let u = obj["usage"] as? [String: Any] {
            let read = u["cache_read_input_tokens"] as? Int ?? 0
            let created = u["cache_creation_input_tokens"] as? Int ?? 0
            usage.input = (u["input_tokens"] as? Int ?? 0) + read + created
            usage.output = u["output_tokens"] as? Int ?? 0
            usage.cached = read
        }
        return ModelReply(text: text, usage: usage)
    }
}
