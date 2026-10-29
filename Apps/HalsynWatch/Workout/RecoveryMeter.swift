import Foundation
import HalsynCore
import HealthKit
import Observation
import WatchKit

/// Mide cómo baja el pulso justo después de terminar (recuperación de la FC).
///
/// Al guardar el entrenamiento se abre una sesión corta de enfriamiento
/// (`HKWorkoutActivityType.cooldown`) solo para tener el pulso cada pocos
/// segundos; esa sesión se descarta y no queda como entrenamiento en Salud.
/// Al final se pregunta si guardar la medición: si sí, se guarda en la app y se
/// envía al iPhone. No va a la «Recuperación cardíaca» de Salud: la de Apple es
/// una estimación normalizada a una intensidad estándar y mezclarlas confundiría.
@MainActor
@Observable
final class RecoveryMeter: NSObject {
    enum Phase: Equatable {
        case measuring
        case finished(HeartRateRecoveryResult)
        case failed(String)
    }

    enum SaveState: Equatable {
        case pending, saving, saved, notSaved
        case failed(String)
    }

    private(set) var phase: Phase?
    private(set) var samples: [RecoverySample] = []
    private(set) var currentHeartRate: Double?
    private(set) var endHeartRate: Double = 0
    /// Fin del ejercicio: los segundos de recuperación se cuentan desde aquí.
    private(set) var exerciseEnd: Date = .now
    private(set) var duration: TimeInterval = 120
    private(set) var saveState: SaveState = .pending

    @ObservationIgnored private let healthStore: HKHealthStore
    @ObservationIgnored private var session: HKWorkoutSession?
    @ObservationIgnored private var builder: HKLiveWorkoutBuilder?
    @ObservationIgnored private var ticker: Task<Void, Never>?
    @ObservationIgnored private var announcedMinute = false

    init(healthStore: HKHealthStore) {
        self.healthStore = healthStore
        super.init()
    }

    var isActive: Bool { phase != nil }

    /// Segundos desde el fin del ejercicio.
    func elapsed(at date: Date) -> TimeInterval {
        max(0, date.timeIntervalSince(exerciseEnd))
    }

    func start(endHeartRate: Double, exerciseEnd: Date, minutes: Int) async {
        guard phase == nil else { return }
        self.endHeartRate = endHeartRate
        self.exerciseEnd = exerciseEnd
        duration = TimeInterval(max(1, minutes) * 60)
        samples = [RecoverySample(elapsed: 0, bpm: endHeartRate)]
        currentHeartRate = endHeartRate
        saveState = .pending
        announcedMinute = false
        phase = .measuring
        do {
            let configuration = HKWorkoutConfiguration()
            configuration.activityType = .cooldown
            configuration.locationType = .unknown
            let session = try HKWorkoutSession(healthStore: healthStore, configuration: configuration)
            let builder = session.associatedWorkoutBuilder()
            builder.dataSource = HKLiveWorkoutDataSource(healthStore: healthStore, workoutConfiguration: configuration)
            session.delegate = self
            builder.delegate = self
            self.session = session
            self.builder = builder
            let now = Date()
            session.startActivity(with: now)
            try await builder.beginCollection(at: now)
            startTicker()
        } catch {
            phase = .failed(error.localizedDescription)
            await stopSession()
        }
    }

    /// Terminar antes de tiempo (con lo medido hasta ahora).
    func stopEarly() {
        Task { await finish() }
    }

    /// Guarda la medición en el reloj y la envía al iPhone (solo si llegó al minuto).
    func save() async {
        guard case let .finished(result) = phase, result.oneMinute != nil else {
            saveState = .notSaved
            return
        }
        RecoveryHistoryStore.shared.add(result)
        RunSettingsStore.shared.sendRecovery(result)
        saveState = .saved
    }

    func discard() {
        saveState = .notSaved
    }

    /// Vuelve al estado inicial (después de guardar o no guardar).
    func close() {
        ticker?.cancel()
        ticker = nil
        phase = nil
        samples = []
        currentHeartRate = nil
        saveState = .pending
    }

    // MARK: Medición

    private func startTicker() {
        ticker?.cancel()
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self, !Task.isCancelled else { return }
                self.tick(at: .now)
            }
        }
    }

    private func tick(at date: Date) {
        guard phase == .measuring else { return }
        let elapsed = elapsed(at: date)
        if elapsed >= 60, !announcedMinute {
            announcedMinute = true
            WKInterfaceDevice.current().play(.notification)
            if let bpm = HeartRateRecovery.heartRate(at: 60, in: samples) {
                let count = Int((endHeartRate - bpm).rounded())
                VoiceCoach.shared.say(String(localized: "Un minuto: el pulso bajó \(count) pulsaciones"))
            }
        }
        if elapsed >= duration {
            Task { await finish() }
        }
    }

    fileprivate func received(heartRate bpm: Double, at date: Date) {
        guard phase == .measuring, HeartRateRecovery.plausibleBPM.contains(bpm) else { return }
        currentHeartRate = bpm
        samples.append(RecoverySample(elapsed: elapsed(at: date), bpm: bpm))
    }

    private func finish() async {
        guard phase == .measuring else { return }
        ticker?.cancel()
        ticker = nil
        let result = HeartRateRecovery.result(date: exerciseEnd, endHeartRate: endHeartRate, samples: samples)
        phase = .finished(result)
        WKInterfaceDevice.current().play(.success)
        await stopSession()
    }

    /// Cierra la sesión de enfriamiento sin guardarla como entrenamiento.
    private func stopSession() async {
        let builder = self.builder
        let session = self.session
        self.builder = nil
        self.session = nil
        session?.end()
        if let builder {
            try? await builder.endCollection(at: .now)
            builder.discardWorkout()
        }
    }
}

extension RecoveryMeter: HKWorkoutSessionDelegate {
    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didChangeTo toState: HKWorkoutSessionState, from fromState: HKWorkoutSessionState, date: Date) {}

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        let message = error.localizedDescription
        Task { @MainActor in
            if self.phase == .measuring {
                self.phase = .failed(message)
            }
        }
    }
}

extension RecoveryMeter: HKLiveWorkoutBuilderDelegate {
    nonisolated func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}

    nonisolated func workoutBuilder(_ workoutBuilder: HKLiveWorkoutBuilder, didCollectDataOf collectedTypes: Set<HKSampleType>) {
        let heartRateType = HKQuantityType(.heartRate)
        guard collectedTypes.contains(heartRateType),
              let bpm = workoutBuilder.statistics(for: heartRateType)?.mostRecentQuantity()?.doubleValue(for: HKUnit.count().unitDivided(by: .minute())) else { return }
        let now = Date()
        Task { @MainActor in
            self.received(heartRate: bpm, at: now)
        }
    }
}
