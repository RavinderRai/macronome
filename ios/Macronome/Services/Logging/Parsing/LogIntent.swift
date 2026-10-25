import Foundation

/// Question or log, decided by rule so it costs nothing and never waits on a model.
enum LogIntent {
    static let questionStarts = [
        "what", "whats", "how", "can", "should", "could", "would", "any ideas", "plan", "suggest", "help", "why",
        "which", "is there", "is it", "do i", "am i", "will",
    ]

    static func of(_ text: String) -> Intent {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.hasSuffix("?") { return .question }
        let words = t.lowercased().replacingOccurrences(of: "’", with: "").replacingOccurrences(of: "'", with: "")
            .split { !$0.isLetter && !$0.isNumber }.map(String.init)
        let head = words.prefix(3).joined(separator: " ")
        // "Can of beans" and "half a can" are logs.
        if words.first == "can", words.dropFirst().first == "of" { return .log }
        return questionStarts.contains { head == $0 || head.hasPrefix($0 + " ") } ? .question : .log
    }
}
