import Foundation
import Observation

/// On-device speech to text for the Listening panel.
/// Contract: `start()` asks for permission and begins streaming into `transcript`;
/// `stop()` ends and returns the final text; `level` is 0...1 for the meter.
@MainActor
@Observable
final class SpeechRecognizer {
    private(set) var transcript = ""
    private(set) var isListening = false
    private(set) var level: Float = 0
    private(set) var error: String?

    func start() async {}
    @discardableResult func stop() -> String { isListening = false; return transcript }
    func reset() { transcript = "" }
}
