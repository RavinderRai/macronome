import Foundation

/// The fast-tier fallback for logs the local parser could not resolve. Every id the
/// model returns is checked against the ledger before it reaches the logging flow.
struct AILogInterpreter: LogInterpreter {
    enum Backend: Sendable {
        case cloud(any ModelProvider)
        case onDevice
    }

    var backend: Backend
    /// Usage is recorded on the router, which lives on the main actor.
    var record: @Sendable (String, ModelUsage) async -> Void

    func interpret(_ text: String, ledger: Ledger) async throws -> [ParsedItem] {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return [] }
        let raw: [InterpretedItem]
        switch backend {
        case .cloud(let provider):
            do {
                let reply = try await provider.complete(InterpreterPrompt.request(t, ledger: ledger))
                await record(provider.usageKey, reply.usage)
                raw = InterpreterPrompt.parse(reply.text)
            } catch let e as ProviderError {
                throw ModelError(e)
            }
        case .onDevice:
            #if canImport(FoundationModels)
            do {
                raw = try await OnDeviceInterpreter.items(t, ledger: ledger)
                await record("On-device", ModelUsage())
            } catch let e as ProviderError {
                throw ModelError(e)
            }
            #else
            throw ModelError.unsupported("The on-device model needs iOS 26.")
            #endif
        }
        return InterpreterPrompt.validate(raw, text: t, ledger: ledger)
    }
}

extension ModelError {
    init(_ e: ProviderError) {
        switch e {
        case .unsupported(let s), .network(let s): self = .unsupported(s)
        case .badResponse(let s): self = .badResponse(s)
        case .http(let code, let s): self = .http(code, s)
        }
    }
}
