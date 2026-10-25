import Foundation
import Testing
@testable import HalsynCore

@Suite("Voz del entrenador")
struct CoachVoiceTests {
    let voices = [
        VoiceCandidate(identifier: "monica", language: "es-ES", quality: .premium),
        VoiceCandidate(identifier: "paulina", language: "es-MX", quality: .standard),
        VoiceCandidate(identifier: "paulina-plus", language: "es-MX", quality: .enhanced),
        VoiceCandidate(identifier: "whisper", language: "es-MX", quality: .premium, isNoveltyOrPersonal: true),
        VoiceCandidate(identifier: "samantha", language: "en-US", quality: .standard),
        VoiceCandidate(identifier: "alva", language: "sv-SE", quality: .standard),
    ]

    @Test func latinAmericanBeforeSpainEvenIfLowerQuality() {
        #expect(CoachVoicePicker.choose(voices, languageCode: "es")?.identifier == "paulina-plus")
    }

    @Test func rioplatenseFirstWhenAvailable() {
        let more = voices + [VoiceCandidate(identifier: "uy", language: "es_UY", quality: .standard)]
        #expect(CoachVoicePicker.choose(more, languageCode: "es")?.identifier == "uy")
    }

    @Test func spainOnlyAsLastResort() {
        let onlySpain = [VoiceCandidate(identifier: "monica", language: "es-ES", quality: .standard)]
        #expect(CoachVoicePicker.choose(onlySpain, languageCode: "es")?.identifier == "monica")
    }

    @Test func otherLanguages() {
        #expect(CoachVoicePicker.choose(voices, languageCode: "en")?.identifier == "samantha")
        #expect(CoachVoicePicker.choose(voices, languageCode: "sv")?.identifier == "alva")
        #expect(CoachVoicePicker.choose(voices, languageCode: "fr") == nil)
    }

    @Test func voiceDefaultsToThePhone() throws {
        var settings = RunSettings()
        #expect(settings.voiceRoute == .phone)
        settings.voiceRoute = .watch
        let decoded = try RunSettings.decoded(from: settings.encoded())
        #expect(decoded.voiceRoute == .watch)
    }
}
