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

@Suite("Avisos de voz elegibles")
struct VoiceCueSettingsTests {
    @Test func defaultsKeepTheCurrentBehaviour() {
        let cues = RunSettings().cues
        #expect(cues.laps && cues.lapEvery == 1 && cues.lapPace && cues.heartRate && cues.intervals && cues.alerts)
        #expect(!cues.averagePace && !cues.elapsedTime)
        #expect((1...4).allSatisfy(cues.speaksLap))
    }

    @Test func everyNthLap() {
        var cues = VoiceCueSettings(lapEvery: 5)
        #expect(!cues.speaksLap(1) && !cues.speaksLap(4) && cues.speaksLap(5) && cues.speaksLap(10))
        cues.laps = false
        #expect(!cues.speaksLap(5))
        #expect(VoiceCueSettings(lapEvery: 0).lapEvery == 1)
    }

    @Test func roundTripAndOldSettings() throws {
        var settings = RunSettings()
        settings.cues = VoiceCueSettings(lapEvery: 2, heartRate: false, alerts: false)
        let decoded = try RunSettings.decoded(from: settings.encoded())
        #expect(decoded.cues == settings.cues)
        // Ajustes de antes: sin la clave, los avisos de siempre.
        var json = try #require(try JSONSerialization.jsonObject(with: RunSettings().encoded()) as? [String: Any])
        json.removeValue(forKey: "voiceCues")
        #expect(try RunSettings.decoded(from: JSONSerialization.data(withJSONObject: json)).cues == VoiceCueSettings())
        // Una clave nueva que falte dentro de los avisos toma su valor por defecto.
        let partial = try JSONDecoder().decode(VoiceCueSettings.self, from: Data(#"{"laps":true,"lapEvery":3}"#.utf8))
        #expect(partial.lapEvery == 3 && partial.heartRate && partial.alerts)
    }
}
