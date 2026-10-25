import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Redacción con el modelo de lenguaje de Apple (Apple Intelligence), que
/// corre en el iPhone: no sale ningún dato del dispositivo. Disponible con
/// iOS 26, un iPhone compatible y Apple Intelligence activado; si no, la app
/// muestra solo los datos.
enum OnDeviceNarrator {
    enum Status: Equatable {
        case available
        /// El iPhone es compatible pero Apple Intelligence está desactivado.
        case notEnabled
        /// El modelo aún se está descargando o preparando.
        case notReady
        /// iPhone no compatible, iOS anterior al 26 o idioma no admitido.
        case unavailable
    }

    /// Idiomas de la app que admite el modelo de Apple (hindi aún no).
    static let supportedLanguages: Set<String> = ["es", "en", "pt", "fr", "it", "sv", "da", "zh"]

    static var languageCode: String { Locale.current.language.languageCode?.identifier ?? "en" }

    static var status: Status {
        guard supportedLanguages.contains(languageCode) else { return .unavailable }
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            switch SystemLanguageModel.default.availability {
            case .available:
                return .available
            case .unavailable(let reason):
                switch reason {
                case .appleIntelligenceNotEnabled: return .notEnabled
                case .modelNotReady: return .notReady
                default: return .unavailable
                }
            }
        }
        #endif
        return .unavailable
    }

    /// Texto generado, o `nil` si no hay modelo o falla.
    static func write(instructions: String, prompt: String) async -> String? {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            guard status == .available else { return nil }
            do {
                let session = LanguageModelSession(instructions: instructions)
                let response = try await session.respond(to: prompt, options: GenerationOptions(temperature: 0.3))
                return response.content
            } catch {
                return nil
            }
        }
        #endif
        return nil
    }

    /// Nombre del idioma actual en inglés, para las instrucciones del modelo.
    static var languageName: String {
        Locale(identifier: "en").localizedString(forLanguageCode: languageCode) ?? "English" // nolocalize
    }
}
