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

    /// En bici: "Kilómetro 25. Últimos 5 a 28,1 kilómetros por hora. Pulso 140".
    static func rideLap(_ lap: Lap, autoLap: Double?, heartRate: Double?, unit: UnitSystem) -> String {
        let count = Int(((autoLap ?? lap.distance) / unit.metersPerDistanceUnit).rounded())
        var parts: [String]
        if count > 0 {
            let number = lap.index * count
            parts = [unit == .imperial ? String(localized: "Milla \(number)") : String(localized: "Kilómetro \(number)")]
        } else {
            parts = [String(localized: "Vuelta \(lap.index)")]
        }
        if let speed = Speed(pace: lap.pace) {
            let value = speed.formatted(in: unit)
            if count > 0 {
                parts.append(unit == .imperial ? String(localized: "Últimas \(count) a \(value) millas por hora") : String(localized: "Últimos \(count) a \(value) kilómetros por hora"))
            } else {
                parts.append(unit == .imperial ? String(localized: "A \(value) millas por hora") : String(localized: "A \(value) kilómetros por hora"))
            }
        }
        if let heartRate {
            let beats = Int(heartRate.rounded())
            parts.append(String(localized: "Pulso \(beats)"))
        }
        return parts.joined(separator: ". ")
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
