import AVFoundation
import HalsynCore
import UIKit

/// Dice en el iPhone los avisos que manda el reloj durante la carrera: así se
/// oyen por los auriculares conectados al teléfono, encima de la música.
///
/// El reloj despierta la app en segundo plano solo un momento. Por eso:
/// - se pide tiempo extra a iOS mientras se habla (si no, la app se dormía con
///   la música ya bajada y la voz no llegaba a sonar);
/// - se responde al reloj recién cuando la voz **empezó de verdad** (si no
///   empieza en 2 s, el reloj lo dice él mismo);
/// - la música vuelve siempre, aunque el sistema no avise que terminó.
@MainActor
final class CoachSpeaker: NSObject, AVSpeechSynthesizerDelegate {
    static let shared = CoachSpeaker()

    /// Si la voz no empezó en este tiempo, se da por fallida.
    static let startTimeout: Duration = .seconds(2)

    private var synthesizer = AVSpeechSynthesizer()
    /// Quien espera saber si empezó a hablar, por frase.
    private var waitingStart: [ObjectIdentifier: (Bool) -> Void] = [:]
    private var backgroundTask: UIBackgroundTaskIdentifier = .invalid
    private var releaseTask: Task<Void, Never>?

    override private init() {
        super.init()
        synthesizer.delegate = self
    }

    /// Dice el aviso. `started` (opcional) recibe `true` cuando la voz empezó a
    /// sonar, o `false` si no se pudo (entonces el reloj lo dice él mismo).
    func say(_ text: String, started: ((Bool) -> Void)? = nil) {
        guard CoachSpeech.activateAudio() else {
            started?(false)
            return
        }
        if backgroundTask == .invalid {
            backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "coach-voice") { [weak self] in  // nolocalize
                Task { @MainActor in self?.release() }
            }
        }
        releaseTask?.cancel()
        let utterance = CoachSpeech.utterance(text)
        let id = ObjectIdentifier(utterance)
        waitingStart[id] = { result in started?(result) }
        synthesizer.speak(utterance)
        Task { [weak self] in
            try? await Task.sleep(for: Self.startTimeout)
            self?.startTimedOut(id)
        }
    }

    /// No empezó a sonar: se descarta ese sintetizador (puede quedar trabado tras
    /// una interrupción del audio) y se devuelve la música.
    private func startTimedOut(_ id: ObjectIdentifier) {
        guard let callback = waitingStart.removeValue(forKey: id) else { return }
        synthesizer.delegate = nil
        synthesizer.stopSpeaking(at: .immediate)
        synthesizer = AVSpeechSynthesizer()
        synthesizer.delegate = self
        callback(false)
        if waitingStart.isEmpty { release() }
    }

    private func didStart(_ id: ObjectIdentifier) {
        waitingStart.removeValue(forKey: id)?(true)
    }

    private func didEnd(_ id: ObjectIdentifier) {
        waitingStart.removeValue(forKey: id)?(false)
        scheduleRelease()
    }

    /// Devuelve la música apenas no queda nada por decir (con un margen por si
    /// llega otra frase enseguida).
    private func scheduleRelease() {
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
        if backgroundTask != .invalid {
            UIApplication.shared.endBackgroundTask(backgroundTask)
            backgroundTask = .invalid
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        let id = ObjectIdentifier(utterance)
        Task { @MainActor in self.didStart(id) }
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
