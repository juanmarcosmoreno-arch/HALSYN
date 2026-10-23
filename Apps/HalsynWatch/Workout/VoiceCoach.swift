import AVFoundation
import HalsynCore

/// Avisos de voz durante la carrera (auriculares Bluetooth o altavoz del reloj).
/// Baja el volumen de la música mientras habla y lo devuelve al terminar.
@MainActor
final class VoiceCoach: NSObject, AVSpeechSynthesizerDelegate {
    static let shared = VoiceCoach()

    private let synthesizer = AVSpeechSynthesizer()

    override private init() {
        super.init()
        synthesizer.delegate = self
    }

    func say(_ text: String) {
        guard RunSettingsStore.shared.settings.isVoiceEnabled else { return }
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .voicePrompt, options: [.duckOthers, .interruptSpokenAudioAndMixWithOthers])
        try? session.setActive(true)
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: Bundle.main.preferredLocalizations.first ?? Locale.current.identifier)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        synthesizer.speak(utterance)
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in
            guard !self.synthesizer.isSpeaking else { return }
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
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
