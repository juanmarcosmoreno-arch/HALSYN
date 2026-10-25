import AVFoundation
import HalsynCore

/// Avisos de voz durante la carrera. Por defecto los dice el iPhone (por los
/// auriculares conectados al teléfono, encima de la música); si el iPhone no
/// está al alcance o no puede, los dice el reloj (su altavoz o sus auriculares).
@MainActor
final class VoiceCoach: NSObject, AVSpeechSynthesizerDelegate {
    static let shared = VoiceCoach()

    private let synthesizer = AVSpeechSynthesizer()

    override private init() {
        super.init()
        synthesizer.delegate = self
    }

    func say(_ text: String) {
        let settings = RunSettingsStore.shared.settings
        guard settings.isVoiceEnabled else { return }
        if settings.voiceRoute == .phone, RunSettingsStore.shared.speakOnPhone(text, fallback: { [weak self] in self?.speakHere(text) }) {
            return
        }
        speakHere(text)
    }

    private func speakHere(_ text: String) {
        _ = CoachSpeech.activateAudio()
        synthesizer.speak(CoachSpeech.utterance(text))
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in
            guard !self.synthesizer.isSpeaking else { return }
            CoachSpeech.deactivateAudio()
        }
    }

    // MARK: Frases

    /// "5 minutos 12 segundos" (el sintetizador lee mal "5:12").
    static func spoken(_ pace: Pace, unit: UnitSystem) -> String {
        let total = Int(pace.seconds(per: unit).rounded())
        let minutes = total / 60
        let seconds = total % 60
        return String(localized: "\(minutes) minutos \(seconds) segundos")
    }

    static func lap(number: Int, pace: Pace?, heartRate: Double?, unit: UnitSystem) -> String {
        var parts: [String] = [unit == .imperial ? String(localized: "Milla \(number)") : String(localized: "Kilómetro \(number)")]
        if let pace { parts.append(String(localized: "Ritmo \(spoken(pace, unit: unit))")) }
        if let heartRate {
            let beats = Int(heartRate.rounded())
            parts.append(String(localized: "Pulso \(beats)"))
        }
        return parts.joined(separator: ". ")
    }
}
