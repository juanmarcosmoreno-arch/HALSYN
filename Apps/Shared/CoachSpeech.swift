import AVFoundation
import HalsynCore

/// Voz y frases del entrenador, compartidas por el iPhone y el reloj.
enum CoachSpeech {
    /// Idioma de la app ("es", "en", "sv").
    static var languageCode: String {
        let preferred = Bundle.main.preferredLocalizations.first ?? "es"
        return Locale(identifier: preferred).language.languageCode?.identifier ?? "es"
    }

    /// La mejor voz instalada para el idioma de la app; en español, primero
    /// las rioplatenses y latinoamericanas (`CoachVoicePicker`).
    static func bestVoice() -> AVSpeechSynthesisVoice? {
        let candidates = AVSpeechSynthesisVoice.speechVoices().map { voice in
            VoiceCandidate(
                identifier: voice.identifier,
                language: voice.language,
                quality: quality(voice.quality),
                isNoveltyOrPersonal: voice.voiceTraits.contains(.isNoveltyVoice) || voice.voiceTraits.contains(.isPersonalVoice)
            )
        }
        if let chosen = CoachVoicePicker.choose(candidates, languageCode: languageCode),
           let voice = AVSpeechSynthesisVoice(identifier: chosen.identifier) {
            return voice
        }
        return AVSpeechSynthesisVoice(language: languageCode)
    }

    static func utterance(_ text: String) -> AVSpeechUtterance {
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = bestVoice()
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        return utterance
    }

    /// Los avisos bajan la música un momento y la devuelven al terminar.
    static func activateAudio() -> Bool {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .voicePrompt, options: [.duckOthers, .interruptSpokenAudioAndMixWithOthers])
            try session.setActive(true)
            return true
        } catch {
            return false
        }
    }

    static func deactivateAudio() {
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private static func quality(_ quality: AVSpeechSynthesisVoiceQuality) -> VoiceCandidate.Quality {
        switch quality {
        case .premium: .premium
        case .enhanced: .enhanced
        default: .standard
        }
    }
}
