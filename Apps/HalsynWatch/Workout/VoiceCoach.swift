import AVFoundation
import HalsynCore

/// Avisos de voz durante la carrera. Por defecto los dice el iPhone (por los
/// auriculares conectados al teléfono, encima de la música); si el iPhone no
/// está al alcance o no consigue que suene, los dice el reloj (su altavoz o sus
/// auriculares). La música vuelve siempre, aunque la voz no llegue a sonar.
@MainActor
final class VoiceCoach: NSObject, AVSpeechSynthesizerDelegate {
    static let shared = VoiceCoach()

    private var synthesizer = AVSpeechSynthesizer()
    private var waitingStart: Set<ObjectIdentifier> = []
    private var releaseTask: Task<Void, Never>?

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
        guard CoachSpeech.activateAudio() else { return }
        releaseTask?.cancel()
        let utterance = CoachSpeech.utterance(text)
        let id = ObjectIdentifier(utterance)
        waitingStart.insert(id)
        synthesizer.speak(utterance)
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            self?.startTimedOut(id)
        }
    }

    /// No empezó a sonar: se cambia el sintetizador (puede quedar trabado) y vuelve la música.
    private func startTimedOut(_ id: ObjectIdentifier) {
        guard waitingStart.remove(id) != nil else { return }
        synthesizer.delegate = nil
        synthesizer.stopSpeaking(at: .immediate)
        synthesizer = AVSpeechSynthesizer()
        synthesizer.delegate = self
        if waitingStart.isEmpty { release() }
    }

    private func didEnd(_ id: ObjectIdentifier) {
        waitingStart.remove(id)
        releaseTask?.cancel()
        releaseTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled, let self, !self.synthesizer.isSpeaking, self.waitingStart.isEmpty else { return }
            self.release()
        }
    }

    private func release() {
        releaseTask?.cancel()
        releaseTask = nil
        CoachSpeech.deactivateAudio()
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        let id = ObjectIdentifier(utterance)
        Task { @MainActor in self.waitingStart.remove(id) }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        let id = ObjectIdentifier(utterance)
        Task { @MainActor in self.didEnd(id) }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        let id = ObjectIdentifier(utterance)
        Task { @MainActor in self.didEnd(id) }
    }
}
