import Foundation
import Observation

/// Long-lived services shared by screens: speech, the label reader and the model
/// router. Kept in the environment so previews can swap them.
@MainActor
@Observable
final class AppServices {
    let models = ModelRouter()
    let speech = SpeechRecognizer()
}
