import Foundation

// Tool calling: the request and reply shapes the chat agent uses, and how each service
// encodes them. Plain chat (`complete`) is untouched; a provider that has no tool
// support (the on-device model) keeps the default `respond`, which throws.

/// A tool the model may call, with a JSON Schema for its input.
struct ToolSpec: Sendable {
    var name: String
    var description: String
    var parameters: JSONValue
}

struct ToolCall: Hashable, Sendable {
    var id: String
    var name: String
    var arguments: [String: JSONValue]
}

/// One item of the conversation the agent sends. Assistant items keep the service's
/// own content (`raw`) so a turn is replayed exactly as it came back, thinking blocks
/// included; earlier days' turns are sent as plain text.
enum AgentItem: Sendable {
    case user(String)
    case assistant(text: String, calls: [ToolCall], raw: JSONValue?)
    case results([ToolResult])
}

struct ToolResult: Hashable, Sendable {
    var callID: String
    var name: String
    var content: String
    var isError = false
}

struct AgentRequest: Sendable {
    var system: [String]
    var items: [AgentItem]
    var tools: [ToolSpec]
    var maxTokens = 4000
    var effort: String? = "low"
    var timeout: TimeInterval = 90
}

struct AgentReply: Sendable {
    var text: String
    var calls: [ToolCall]
    /// The assistant turn as the service returned it, for replay.
    var raw: JSONValue?
    var usage: ModelUsage
}

extension ModelProvider {
    var supportsTools: Bool { false }
    func respond(_ request: AgentRequest) async throws -> AgentReply {
        throw ProviderError.unsupported("This model can't use tools.")
    }
}

extension JSONValue: ExpressibleByArrayLiteral, ExpressibleByDictionaryLiteral {
    init(arrayLiteral elements: JSONValue...) { self = .array(elements) }
    init(dictionaryLiteral elements: (String, JSONValue)...) {
        self = .object(Dictionary(elements, uniquingKeysWith: { _, b in b }))
    }
}

extension JSONValue {
    /// Plain Foundation value, for JSONSerialization.
    var foundation: Any {
        switch self {
        case .null: return NSNull()
        case .bool(let b): return b
        case .number(let n): return n == n.rounded() && abs(n) < 1e15 ? Int(n) as Any : n as Any
        case .string(let s): return s
        case .array(let a): return a.map(\.foundation)
        case .object(let o): return o.mapValues(\.foundation)
        }
    }

    init(foundation any: Any?) {
        switch any {
        case nil, is NSNull: self = .null
        case let n as NSNumber:
            if CFGetTypeID(n) == CFBooleanGetTypeID() { self = .bool(n.boolValue) } else { self = .number(n.doubleValue) }
        case let s as String: self = .string(s)
        case let a as [Any]: self = .array(a.map { JSONValue(foundation: $0) })
        case let o as [String: Any]: self = .object(o.mapValues { JSONValue(foundation: $0) })
        default: self = .null
        }
    }

    /// Compact JSON text, keys sorted so the same value always reads the same.
    var jsonText: String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return (try? encoder.encode(self)).flatMap { String(data: $0, encoding: .utf8) } ?? "null"
    }

    static func parse(_ text: String) -> JSONValue? {
        guard let data = text.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(JSONValue.self, from: data)
    }
}

// MARK: - OpenAI-compatible

extension OpenAICompatibleProvider {
    var supportsTools: Bool { true }

    func agentBody(_ r: AgentRequest, maxKey: String = "max_tokens") -> [String: Any] {
        var messages: [[String: Any]] = []
        let system = r.system.joined(separator: "\n\n")
        if !system.isEmpty { messages.append(["role": "system", "content": system]) }
        for item in r.items {
            switch item {
            case .user(let text):
                messages.append(["role": "user", "content": text])
            case .assistant(let text, let calls, let raw):
                if let raw = raw?.foundation as? [String: Any] {
                    messages.append(raw)
                    continue
                }
                var m: [String: Any] = ["role": "assistant", "content": text.isEmpty && !calls.isEmpty ? NSNull() : text]
                if !calls.isEmpty {
                    m["tool_calls"] = calls.map { c in
                        ["id": c.id, "type": "function",
                         "function": ["name": c.name, "arguments": JSONValue.object(c.arguments).jsonText]] as [String: Any]
                    }
                }
                messages.append(m)
            case .results(let results):
                for res in results {
                    messages.append(["role": "tool", "tool_call_id": res.callID, "content": res.content])
                }
            }
        }
        var body: [String: Any] = ["model": model, "messages": messages, maxKey: r.maxTokens]
        if !r.tools.isEmpty {
            body["tools"] = r.tools.map { t in
                ["type": "function",
                 "function": ["name": t.name, "description": t.description, "parameters": t.parameters.foundation]] as [String: Any]
            }
        }
        return body
    }

    func respond(_ r: AgentRequest) async throws -> AgentReply {
        guard let url = HTTP.endpoint(baseURL, appending: "/chat/completions") else {
            throw ProviderError.unsupported("Add a base URL in Settings → Models.")
        }
        var headers: [String: String] = [:]
        if let apiKey, !apiKey.isEmpty { headers["Authorization"] = "Bearer \(apiKey)" }
        if url.host()?.contains("openrouter") == true { headers["X-Title"] = "Macronome" }
        var maxKey = "max_tokens"
        for attempt in 0..<2 {
            let (status, data) = try await HTTP.post(url, headers: headers, body: agentBody(r, maxKey: maxKey), timeout: r.timeout)
            if status == 200 { return try Self.parseAgent(data) }
            let msg = (ProviderError.providerMessage(data) ?? "").lowercased()
            if status == 400, attempt == 0, msg.contains("max_tokens") || msg.contains("max_completion_tokens") {
                maxKey = "max_completion_tokens"
                continue
            }
            throw ProviderError.friendly(status: status, body: data)
        }
        throw ProviderError.badResponse("no answer")
    }

    static func parseAgent(_ data: Data) throws -> AgentReply {
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
        let calls: [ToolCall] = (message["tool_calls"] as? [[String: Any]] ?? []).enumerated().compactMap { i, c in
            guard let fn = c["function"] as? [String: Any], let name = fn["name"] as? String else { return nil }
            let args: [String: JSONValue]
            if let s = fn["arguments"] as? String {
                args = JSONValue.parse(s)?.object ?? [:]
            } else {
                args = JSONValue(foundation: fn["arguments"]).object ?? [:]
            }
            return ToolCall(id: c["id"] as? String ?? "call_\(i)", name: name, arguments: args)
        }
        if text.isEmpty, calls.isEmpty, let refusal = message["refusal"] as? String { throw ProviderError.unsupported(refusal) }
        // Replay only what the API accepts back: role, content and tool calls.
        var raw: [String: Any] = ["role": "assistant", "content": message["content"] ?? NSNull()]
        if let tc = message["tool_calls"] { raw["tool_calls"] = tc }
        var usage = ModelUsage()
        if let u = obj["usage"] as? [String: Any] {
            usage.input = u["prompt_tokens"] as? Int ?? 0
            usage.output = u["completion_tokens"] as? Int ?? 0
            usage.cached = (u["prompt_tokens_details"] as? [String: Any])?["cached_tokens"] as? Int ?? 0
        }
        return AgentReply(text: text, calls: calls, raw: JSONValue(foundation: raw), usage: usage)
    }
}

// MARK: - Anthropic

extension AnthropicProvider {
    var supportsTools: Bool { true }

    func agentBody(_ r: AgentRequest, effort: Bool) -> [String: Any] {
        var system: [[String: Any]] = []
        for (i, part) in r.system.enumerated() where !part.isEmpty {
            var block: [String: Any] = ["type": "text", "text": part]
            if i == 0 && r.system.count > 1 { block["cache_control"] = ["type": "ephemeral"] }
            system.append(block)
        }
        var messages: [[String: Any]] = []
        func add(_ role: String, _ content: [[String: Any]]) {
            if let last = messages.last, last["role"] as? String == role, var c = last["content"] as? [[String: Any]] {
                c.append(contentsOf: content)
                messages[messages.count - 1]["content"] = c
            } else {
                messages.append(["role": role, "content": content])
            }
        }
        for item in r.items {
            switch item {
            case .user(let text):
                add("user", [["type": "text", "text": text]])
            case .assistant(let text, let calls, let raw):
                if let blocks = raw?.foundation as? [[String: Any]] {
                    messages.append(["role": "assistant", "content": blocks])
                    continue
                }
                var blocks: [[String: Any]] = []
                if !text.isEmpty { blocks.append(["type": "text", "text": text]) }
                for c in calls {
                    blocks.append(["type": "tool_use", "id": c.id, "name": c.name, "input": JSONValue.object(c.arguments).foundation])
                }
                if !blocks.isEmpty { messages.append(["role": "assistant", "content": blocks]) }
            case .results(let results):
                add("user", results.map { res in
                    var b: [String: Any] = ["type": "tool_result", "tool_use_id": res.callID, "content": res.content]
                    if res.isError { b["is_error"] = true }
                    return b
                })
            }
        }
        // Cache the conversation so far, so each tool round reads it at the cache rate.
        if var last = messages.last, var content = last["content"] as? [[String: Any]], !content.isEmpty {
            content[content.count - 1]["cache_control"] = ["type": "ephemeral"]
            last["content"] = content
            messages[messages.count - 1] = last
        }
        var body: [String: Any] = ["model": model, "max_tokens": r.maxTokens, "messages": messages]
        if !system.isEmpty { body["system"] = system }
        if !r.tools.isEmpty {
            body["tools"] = r.tools.map { ["name": $0.name, "description": $0.description, "input_schema": $0.parameters.foundation] }
        }
        if effort, let e = r.effort { body["output_config"] = ["effort": e] }
        return body
    }

    func respond(_ r: AgentRequest) async throws -> AgentReply {
        guard let url else { throw ProviderError.unsupported("The Anthropic base URL is not valid.") }
        let headers = ["x-api-key": apiKey, "anthropic-version": Self.version]
        var effort = r.effort != nil
        for attempt in 0..<2 {
            let (status, data) = try await HTTP.post(url, headers: headers, body: agentBody(r, effort: effort), timeout: r.timeout)
            if status == 200 { return try Self.parseAgent(data) }
            let msg = (ProviderError.providerMessage(data) ?? "").lowercased()
            if status == 400, attempt == 0, effort, msg.contains("effort") || msg.contains("output_config") {
                effort = false
                continue
            }
            throw ProviderError.friendly(status: status, body: data)
        }
        throw ProviderError.badResponse("no answer")
    }

    static func parseAgent(_ data: Data) throws -> AgentReply {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = obj["content"] as? [[String: Any]] else {
            throw ProviderError.badResponse("no content in the reply")
        }
        if obj["stop_reason"] as? String == "refusal" {
            throw ProviderError.unsupported("The model declined to answer that.")
        }
        let text = content.filter { $0["type"] as? String == "text" }.compactMap { $0["text"] as? String }.joined()
        let calls = content.filter { $0["type"] as? String == "tool_use" }.compactMap { b -> ToolCall? in
            guard let id = b["id"] as? String, let name = b["name"] as? String else { return nil }
            return ToolCall(id: id, name: name, arguments: JSONValue(foundation: b["input"]).object ?? [:])
        }
        var usage = ModelUsage()
        if let u = obj["usage"] as? [String: Any] {
            let read = u["cache_read_input_tokens"] as? Int ?? 0
            let created = u["cache_creation_input_tokens"] as? Int ?? 0
            usage.input = (u["input_tokens"] as? Int ?? 0) + read + created
            usage.output = u["output_tokens"] as? Int ?? 0
            usage.cached = read
        }
        // Thinking blocks stay in `raw` untouched; the API needs them back as they were.
        return AgentReply(text: text, calls: calls, raw: JSONValue(foundation: content), usage: usage)
    }
}
