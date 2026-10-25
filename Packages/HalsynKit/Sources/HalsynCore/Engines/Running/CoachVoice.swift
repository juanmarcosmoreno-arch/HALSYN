import Foundation

/// Dónde se dicen los avisos de voz de la carrera.
public enum VoiceOutput: String, Codable, CaseIterable, Hashable, Sendable {
    /// En el iPhone (auriculares conectados al teléfono). Si no está al
    /// alcance, habla el reloj.
    case phone
    /// En el reloj (su altavoz o los auriculares conectados a él).
    case watch
}

/// Una voz del sistema, descrita sin depender de AVFoundation.
public struct VoiceCandidate: Hashable, Sendable {
    public enum Quality: Int, Comparable, Sendable {
        case standard = 0, enhanced = 1, premium = 2
        public static func < (lhs: Quality, rhs: Quality) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    public let identifier: String
    /// BCP 47, p. ej. "es-MX".
    public let language: String
    public let quality: Quality
    /// Voces "de broma" (susurro, robot…) o la voz personal del usuario.
    public let isNoveltyOrPersonal: Bool

    public init(identifier: String, language: String, quality: Quality, isNoveltyOrPersonal: Bool = false) {
        self.identifier = identifier
        self.language = language
        self.quality = quality
        self.isNoveltyOrPersonal = isNoveltyOrPersonal
    }
}

/// Elige la voz del entrenador para el idioma de la app.
///
/// En español se prefieren, por este orden, variantes rioplatenses (Uruguay,
/// Argentina), latinoamericanas (es-419, México, EE. UU. y otras) y, solo si
/// no hay otra, la de España. Dentro de cada variante gana la de más
/// calidad (premium > mejorada > estándar).
public enum CoachVoicePicker {
    public static func regionPreference(for languageCode: String) -> [String] {
        switch languageCode {
        case "es": ["es-UY", "es-AR", "es-419", "es-MX", "es-US", "es-CO", "es-CL"] // nolocalize
        case "en": ["en-US", "en-GB", "en-AU", "en-IE", "en-CA"] // nolocalize
        case "sv": ["sv-SE"] // nolocalize
        default: []
        }
    }

    /// Variantes que van al final aunque coincidan con el idioma.
    static func isLastResort(_ language: String) -> Bool {
        language == "es-ES" // nolocalize
    }

    public static func choose(_ voices: [VoiceCandidate], languageCode: String) -> VoiceCandidate? {
        let preference = regionPreference(for: languageCode)
        func normalized(_ language: String) -> String { language.replacingOccurrences(of: "_", with: "-") }
        func rank(_ voice: VoiceCandidate) -> Int {
            let language = normalized(voice.language)
            if let index = preference.firstIndex(of: language) { return index }
            return isLastResort(language) ? 1000 : 500
        }
        return voices
            .filter { !$0.isNoveltyOrPersonal && normalized($0.language).split(separator: "-").first.map(String.init) == languageCode }
            .min { lhs, rhs in
                let (a, b) = (rank(lhs), rank(rhs))
                return a != b ? a < b : lhs.quality > rhs.quality
            }
    }
}
