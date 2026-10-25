import AVFoundation
import Foundation
import Observation
import Speech

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
    /// Food and meal names, so the recognizer leans towards "Gusta" over "Gusto".
    var contextualStrings: [String] = []

    private var engine: AVAudioEngine?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    /// Bumped on every start so callbacks from an earlier session are ignored.
    private var session = 0

    func start() async {
        stopAudio()
        session += 1
        let current = session
        error = nil
        transcript = ""
        level = 0

        guard await Self.speechAuthorized() else {
            error = "Speech recognition is off for Macronome. Turn it on in Settings › Privacy › Speech Recognition, or type instead."
            return
        }
        guard await AVAudioApplication.requestRecordPermission() else {
            error = "Macronome can't use the microphone. Turn it on in Settings › Privacy › Microphone, or type instead."
            return
        }
        guard current == session else { return }
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US")) ?? SFSpeechRecognizer(),
              recognizer.isAvailable else {
            error = "Speech recognition isn't available right now. Type instead."
            return
        }

        do {
            let audio = AVAudioSession.sharedInstance()
            try audio.setCategory(.record, mode: .measurement, options: .duckOthers)
            try audio.setActive(true, options: .notifyOthersOnDeactivation)

            let engine = AVAudioEngine()
            let input = engine.inputNode
            let format = input.outputFormat(forBus: 0)
            guard format.sampleRate > 0, format.channelCount > 0 else {
                throw SpeechError.noMicrophone
            }

            let request = SFSpeechAudioBufferRecognitionRequest()
            request.shouldReportPartialResults = true
            request.addsPunctuation = true
            request.taskHint = .dictation
            request.contextualStrings = Array(contextualStrings.prefix(100))
            if recognizer.supportsOnDeviceRecognition { request.requiresOnDeviceRecognition = true }

            let sink = TapSink(request: request) { [weak self] value in
                Task { @MainActor in
                    guard let self, self.session == current else { return }
                    self.level = value
                }
            }
            input.installTap(onBus: 0, bufferSize: 1024, format: format, block: Self.tapBlock(sink))
            engine.prepare()
            try engine.start()

            self.engine = engine
            self.request = request
            self.task = recognizer.recognitionTask(with: request, resultHandler: Self.resultHandler { [weak self] text, final, failure in
                Task { @MainActor in
                    guard let self, self.session == current else { return }
                    if let text { self.transcript = text }
                    if let failure, self.isListening, !Self.isBenign(failure) {
                        self.error = "Listening stopped: \(failure.localizedDescription)"
                        self.stopAudio()
                    }
                    if final { self.stopAudio() }
                }
            })
            isListening = true
        } catch SpeechError.noMicrophone {
            error = "No microphone is available here. Type instead."
            stopAudio()
        } catch {
            self.error = "Couldn't start listening: \(error.localizedDescription)"
            stopAudio()
        }
    }

    @discardableResult func stop() -> String {
        request?.endAudio()
        stopAudio()
        return transcript.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func reset() {
        stopAudio()
        session += 1
        transcript = ""
        error = nil
        level = 0
    }

    private func stopAudio() {
        if let engine {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
        }
        task?.finish()
        engine = nil
        request = nil
        task = nil
        isListening = false
        level = 0
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    // MARK: callbacks off the main actor

    private enum SpeechError: Error { case noMicrophone }

    /// Holds what the audio thread needs; the request is fed only from that thread.
    private final class TapSink: @unchecked Sendable {
        let request: SFSpeechAudioBufferRecognitionRequest
        let onLevel: @Sendable (Float) -> Void
        init(request: SFSpeechAudioBufferRecognitionRequest, onLevel: @escaping @Sendable (Float) -> Void) {
            self.request = request
            self.onLevel = onLevel
        }
    }

    /// Built outside the main actor so the audio thread never trips actor isolation.
    private nonisolated static func tapBlock(_ sink: TapSink) -> AVAudioNodeTapBlock {
        { buffer, _ in
            sink.request.append(buffer)
            guard let data = buffer.floatChannelData?[0] else { return }
            let n = Int(buffer.frameLength)
            guard n > 0 else { return }
            var sum: Float = 0
            for i in 0..<n { sum += data[i] * data[i] }
            let rms = (sum / Float(n)).squareRoot()
            // Roughly -50 dB..0 dB onto 0...1.
            let db = 20 * log10(max(rms, 0.000_01))
            sink.onLevel(max(0, min(1, (db + 50) / 50)))
        }
    }

    private nonisolated static func resultHandler(
        _ deliver: @escaping @Sendable (String?, Bool, Error?) -> Void
    ) -> @Sendable (SFSpeechRecognitionResult?, Error?) -> Void {
        { result, error in
            deliver(result?.bestTranscription.formattedString, result?.isFinal ?? false, error)
        }
    }

    private nonisolated static func speechAuthorized() async -> Bool {
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized: return true
        case .denied, .restricted: return false
        default:
            return await withCheckedContinuation { cont in
                SFSpeechRecognizer.requestAuthorization { cont.resume(returning: $0 == .authorized) }
            }
        }
    }

    /// "No speech detected" and cancellation after stop are not worth showing.
    private nonisolated static func isBenign(_ error: Error) -> Bool {
        let e = error as NSError
        return (e.domain == "kAFAssistantErrorDomain" && [203, 216, 1110, 301].contains(e.code))
            || e.domain == "kLSRErrorDomain" && e.code == 301
    }
}
