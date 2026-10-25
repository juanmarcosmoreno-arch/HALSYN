import AVFoundation
import HalsynCore

/// Dice en el iPhone los avisos que manda el reloj durante la carrera: así se
/// oyen por los auriculares conectados al teléfono, encima de la música.
/// Funciona con la app en segundo plano (modo de audio en segundo plano).
@MainActor
final class CoachSpeaker: NSObject, AVSpeechSynthesizerDelegate {
    static let shared = CoachSpeaker()

    private let synthesizer = AVSpeechSynthesizer()

    override private init() {
        super.init()
        synthesizer.delegate = self
    }

    /// `true` si empezó a hablar; si no, el reloj lo dice él mismo.
    @discardableResult
    func say(_ text: String) -> Bool {
        guard CoachSpeech.activateAudio() else { return false }
        synthesizer.speak(CoachSpeech.utterance(text))
        return true
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in
            guard !self.synthesizer.isSpeaking else { return }
            CoachSpeech.deactivateAudio()
        }
    }
}
