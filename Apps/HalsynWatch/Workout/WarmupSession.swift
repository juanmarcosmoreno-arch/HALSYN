import Foundation
import HalsynCore
import HealthKit
import Observation
import WatchKit

/// Calentamiento antes de un entrenamiento con plan, fuera de lo que se graba.
///
/// Abre una sesión del mismo tipo (carrera o caminata) solo para tener pulso y
/// distancia en vivo; al terminar se descarta, así ni el tiempo ni la distancia
/// del calentamiento quedan en el entrenamiento ni en Salud. Después empieza el
/// entrenamiento de verdad (con su cuenta atrás).
@MainActor
@Observable
final class WarmupSession: NSObject {
    private(set) var goal: IntervalGoal?
    private(set) var startDate: Date?
    private(set) var heartRate: Double?
    private(set) var distance: Double = 0

    @ObservationIgnored private let healthStore: HKHealthStore
    @ObservationIgnored private var session: HKWorkoutSession?
    @ObservationIgnored private var builder: HKLiveWorkoutBuilder?
    @ObservationIgnored private var ticker: Task<Void, Never>?
    @ObservationIgnored private var onFinish: (@MainActor () async -> Void)?

    init(healthStore: HKHealthStore) {
        self.healthStore = healthStore
        super.init()
    }

    var isActive: Bool { goal != nil }

    func elapsed(at date: Date) -> TimeInterval {
        startDate.map { max(0, date.timeIntervalSince($0)) } ?? 0
    }

    /// Fracción que queda (1 = recién empieza); `nil` en un calentamiento abierto.
    func remainingFraction(at date: Date) -> Double? {
        switch goal {
        case let .time(seconds) where seconds > 0:
            return max(0, 1 - elapsed(at: date) / seconds)
        case let .distance(meters) where meters > 0:
            return max(0, 1 - distance / meters)
        default:
            return nil
        }
    }

    /// `onFinish` se llama al cumplirse el calentamiento o al tocar «Empezar ya».
    func start(configuration: HKWorkoutConfiguration, goal: IntervalGoal, onFinish: @escaping @MainActor () async -> Void) async {
        guard !isActive else { return }
        self.goal = goal
        self.onFinish = onFinish
        heartRate = nil
        distance = 0
        startDate = .now
        do {
            let session = try HKWorkoutSession(healthStore: healthStore, configuration: configuration)
            let builder = session.associatedWorkoutBuilder()
            builder.dataSource = HKLiveWorkoutDataSource(healthStore: healthStore, workoutConfiguration: configuration)
            session.delegate = self
            builder.delegate = self
            self.session = session
            self.builder = builder
            let now = Date()
            startDate = now
            session.startActivity(with: now)
            try await builder.beginCollection(at: now)
        } catch {
            // Sin sesión el calentamiento sigue por tiempo (sin pulso ni distancia).
            await stopSession()
        }
        WKInterfaceDevice.current().play(.start)
        VoiceCoach.shared.say(String(localized: "Calentamiento"))
        startTicker()
    }

    /// Termina el calentamiento y empieza el entrenamiento.
    func finish() {
        guard isActive else { return }
        let next = onFinish
        close()
        WKInterfaceDevice.current().play(.notification)
        Task {
            await stopSession()
            await next?()
        }
    }

    /// Cancela todo (no empieza el entrenamiento).
    func cancel() {
        guard isActive else { return }
        close()
        Task { await stopSession() }
    }

    private func close() {
        ticker?.cancel()
        ticker = nil
        goal = nil
        onFinish = nil
        startDate = nil
    }

    private func startTicker() {
        ticker?.cancel()
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self, !Task.isCancelled else { return }
                if let remaining = self.remainingFraction(at: .now), remaining <= 0 {
                    VoiceCoach.shared.say(String(localized: "Calentamiento terminado"))
                    self.finish()
                    return
                }
            }
        }
    }

    /// Cierra la sesión sin guardarla: el calentamiento no queda grabado.
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

    fileprivate func collected(heartRate bpm: Double?, distance meters: Double?) {
        guard isActive else { return }
        if let bpm { heartRate = bpm }
        if let meters { distance = meters }
    }
}

extension WarmupSession: HKWorkoutSessionDelegate {
    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didChangeTo toState: HKWorkoutSessionState, from fromState: HKWorkoutSessionState, date: Date) {}

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {}
}

extension WarmupSession: HKLiveWorkoutBuilderDelegate {
    nonisolated func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}

    nonisolated func workoutBuilder(_ workoutBuilder: HKLiveWorkoutBuilder, didCollectDataOf collectedTypes: Set<HKSampleType>) {
        let heartRateType = HKQuantityType(.heartRate)
        let distanceType = HKQuantityType(.distanceWalkingRunning)
        let bpm = collectedTypes.contains(heartRateType)
            ? workoutBuilder.statistics(for: heartRateType)?.mostRecentQuantity()?.doubleValue(for: HKUnit.count().unitDivided(by: .minute()))
            : nil
        let meters = collectedTypes.contains(distanceType)
            ? workoutBuilder.statistics(for: distanceType)?.sumQuantity()?.doubleValue(for: .meter())
            : nil
        Task { @MainActor in
            self.collected(heartRate: bpm, distance: meters)
        }
    }
}
