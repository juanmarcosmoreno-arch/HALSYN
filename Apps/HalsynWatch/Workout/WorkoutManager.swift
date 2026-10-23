import CoreLocation
import Foundation
import HalsynCore
import HealthKit
import Observation
import WatchKit

/// Gestiona una carrera real en el Apple Watch.
///
/// - `HKWorkoutSession` + `HKLiveWorkoutBuilder`: estado, FC, distancia y energía
///   en vivo; al terminar guarda el entrenamiento en Apple Health (una sola vez:
///   el iPhone nunca escribe entrenamientos, así no hay duplicados).
/// - Core Location + `HKWorkoutRouteBuilder`: ruta GPS en exteriores (solo los
///   puntos que el filtro considera fiables).
/// - `RunSessionTracker` (HalsynCore): ritmo, vueltas y tiempo activo, probado
///   con trazas sintéticas.
/// - Funciona sin el iPhone. Si watchOS relanza la app durante un entrenamiento,
///   `recover()` recupera la sesión activa.
@MainActor
@Observable
final class WorkoutManager: NSObject {
    static let shared = WorkoutManager()

    enum Outcome: Equatable {
        case saved
        case discarded
        case failed(String)
    }

    private(set) var tracker = RunSessionTracker()
    private(set) var isIndoor = false
    private(set) var outcome: Outcome?
    private(set) var errorMessage: String?
    /// Resumen congelado al terminar (para la pantalla final).
    private(set) var finalSnapshot: RunSnapshot?

    var phase: WorkoutPhase { tracker.phase }
    var isActive: Bool { phase == .preparing || phase == .running || phase == .paused || phase == .stopping }

    @ObservationIgnored let healthStore = HKHealthStore()
    @ObservationIgnored private var session: HKWorkoutSession?
    @ObservationIgnored private var builder: HKLiveWorkoutBuilder?
    @ObservationIgnored private var routeBuilder: HKWorkoutRouteBuilder?
    @ObservationIgnored private let locationManager = CLLocationManager()
    @ObservationIgnored private var shouldSave = true

    private override init() {
        super.init()
        locationManager.delegate = self
        locationManager.activityType = .fitness
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.distanceFilter = kCLDistanceFilterNone
    }

    func snapshot(at date: Date) -> RunSnapshot {
        finalSnapshot ?? tracker.snapshot(at: date)
    }

    // MARK: Permisos

    static var shareTypes: Set<HKSampleType> {
        [HKObjectType.workoutType(), HKSeriesType.workoutRoute(), HKQuantityType(.activeEnergyBurned), HKQuantityType(.distanceWalkingRunning)]
    }

    static var readTypes: Set<HKObjectType> {
        [HKQuantityType(.heartRate), HKQuantityType(.activeEnergyBurned), HKQuantityType(.distanceWalkingRunning), HKObjectType.workoutType()]
    }

    private func requestAuthorization() async throws {
        try await healthStore.requestAuthorization(toShare: Self.shareTypes, read: Self.readTypes)
    }

    // MARK: Ciclo de vida

    func start(indoor: Bool) async {
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .running
        configuration.locationType = indoor ? .indoor : .outdoor
        await start(configuration: configuration)
    }

    /// Inicia con una configuración (también la que envía el iPhone con `startWatchApp`).
    func start(configuration: HKWorkoutConfiguration) async {
        guard !isActive else { return }
        reset()
        isIndoor = configuration.locationType == .indoor
        tracker.handle(.start, at: .now)
        do {
            try await requestAuthorization()
            let session = try HKWorkoutSession(healthStore: healthStore, configuration: configuration)
            let builder = session.associatedWorkoutBuilder()
            builder.dataSource = HKLiveWorkoutDataSource(healthStore: healthStore, workoutConfiguration: configuration)
            session.delegate = self
            builder.delegate = self
            self.session = session
            self.builder = builder

            if !isIndoor {
                routeBuilder = HKWorkoutRouteBuilder(healthStore: healthStore, device: nil)
                locationManager.requestWhenInUseAuthorization()
                locationManager.startUpdatingLocation()
            }

            let start = Date()
            session.startActivity(with: start)
            try await builder.beginCollection(at: start)
        } catch {
            fail(error)
        }
    }

    /// Recupera una sesión activa tras un cierre inesperado de la app.
    func recover() async {
        do {
            let recovered: HKWorkoutSession? = try await healthStore.recoverActiveWorkoutSession()
            guard let session = recovered else { return }
            reset()
            let builder = session.associatedWorkoutBuilder()
            session.delegate = self
            builder.delegate = self
            self.session = session
            self.builder = builder
            isIndoor = session.workoutConfiguration.locationType == .indoor
            tracker.handle(.start, at: session.startDate ?? .now)
            tracker.handle(.began, at: session.startDate ?? .now)
            if session.state == .paused {
                tracker.handle(.pause, at: .now)
            }
            if !isIndoor {
                // Los puntos anteriores al cierre no se pueden recuperar: la ruta
                // continúa desde aquí (documentado en RUNNING_ENGINE.md).
                routeBuilder = HKWorkoutRouteBuilder(healthStore: healthStore, device: nil)
                locationManager.startUpdatingLocation()
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func pause() {
        session?.pause()
    }

    func resume() {
        session?.resume()
    }

    func togglePause() {
        phase == .paused ? resume() : pause()
    }

    func markLap() {
        guard tracker.markLap(at: .now) != nil else { return }
        WKInterfaceDevice.current().play(.click)
    }

    /// Termina la carrera. `save == false` la descarta sin escribir en Apple Health.
    func end(save: Bool) {
        shouldSave = save
        locationManager.stopUpdatingLocation()
        if let session {
            session.end()
        } else {
            finalSnapshot = tracker.snapshot(at: .now)
            outcome = .discarded
        }
    }

    /// Vuelve al estado inicial tras ver el resumen.
    func dismissSummary() {
        reset()
    }

    private func reset() {
        tracker = RunSessionTracker()
        outcome = nil
        errorMessage = nil
        finalSnapshot = nil
        shouldSave = true
        session = nil
        builder = nil
        routeBuilder = nil
    }

    private func fail(_ error: Error) {
        locationManager.stopUpdatingLocation()
        tracker.handle(.fail, at: .now)
        errorMessage = error.localizedDescription
        outcome = .failed(error.localizedDescription)
    }

    // MARK: Eventos (en el hilo principal)

    fileprivate func sessionChanged(to state: HKWorkoutSessionState, at date: Date) {
        switch state {
        case .running:
            if tracker.phase == .preparing {
                tracker.handle(.began, at: date)
                WKInterfaceDevice.current().play(.start)
            } else if tracker.phase == .paused {
                tracker.handle(.resume, at: date)
                WKInterfaceDevice.current().play(.start)
            }
        case .paused:
            tracker.handle(.pause, at: date)
            WKInterfaceDevice.current().play(.stop)
        case .stopped:
            tracker.handle(.end, at: date)
        case .ended:
            if tracker.phase != .stopping {
                tracker.handle(.end, at: date)
            }
            Task { await finish(at: date) }
        default:
            break
        }
    }

    private func finish(at date: Date) async {
        locationManager.stopUpdatingLocation()
        guard let builder else { return }
        do {
            try await builder.endCollection(at: date)
            if shouldSave {
                let workout = try await builder.finishWorkout()
                if let workout, let routeBuilder, !isIndoor {
                    _ = try await routeBuilder.finishRoute(with: workout, metadata: nil)
                }
                outcome = .saved
            } else {
                builder.discardWorkout()
                routeBuilder?.discard()
                outcome = .discarded
            }
            tracker.handle(.finished, at: date)
            finalSnapshot = tracker.snapshot(at: date)
            WKInterfaceDevice.current().play(.success)
        } catch {
            fail(error)
            finalSnapshot = tracker.snapshot(at: date)
        }
    }

    fileprivate func collected(distance: Double?, heartRate: Double?, energy: Double?, at date: Date) {
        if let distance {
            tracker.updateDistance(total: distance, at: date)
        }
        if let heartRate {
            tracker.addHeartRate(heartRate)
        }
        if let energy {
            tracker.updateActiveEnergy(total: energy)
        }
        if !tracker.consumeAutoLaps().isEmpty {
            WKInterfaceDevice.current().play(.notification)
        }
    }

    fileprivate func received(locations: [CLLocation]) {
        var reliable: [CLLocation] = []
        for location in locations {
            let sample = LocationSample(
                latitude: location.coordinate.latitude,
                longitude: location.coordinate.longitude,
                altitude: location.verticalAccuracy >= 0 ? location.altitude : nil,
                horizontalAccuracy: location.horizontalAccuracy,
                verticalAccuracy: location.verticalAccuracy >= 0 ? location.verticalAccuracy : nil,
                timestamp: location.timestamp
            )
            if tracker.addLocation(sample) {
                reliable.append(location)
            }
        }
        if !tracker.consumeAutoLaps().isEmpty {
            WKInterfaceDevice.current().play(.notification)
        }
        guard !reliable.isEmpty, let routeBuilder else { return }
        let points = reliable
        Task {
            try? await routeBuilder.insertRouteData(points)
        }
    }
}

// MARK: - Delegados (se llaman fuera del hilo principal)

extension WorkoutManager: HKWorkoutSessionDelegate {
    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didChangeTo toState: HKWorkoutSessionState, from fromState: HKWorkoutSessionState, date: Date) {
        Task { @MainActor in
            self.sessionChanged(to: toState, at: date)
        }
    }

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        let message = error.localizedDescription
        Task { @MainActor in
            self.errorMessage = message
        }
    }
}

extension WorkoutManager: HKLiveWorkoutBuilderDelegate {
    nonisolated func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}

    nonisolated func workoutBuilder(_ workoutBuilder: HKLiveWorkoutBuilder, didCollectDataOf collectedTypes: Set<HKSampleType>) {
        var distance: Double?
        var heartRate: Double?
        var energy: Double?
        for type in collectedTypes {
            guard let quantityType = type as? HKQuantityType, let statistics = workoutBuilder.statistics(for: quantityType) else { continue }
            switch quantityType {
            case HKQuantityType(.distanceWalkingRunning):
                distance = statistics.sumQuantity()?.doubleValue(for: .meter())
            case HKQuantityType(.heartRate):
                heartRate = statistics.mostRecentQuantity()?.doubleValue(for: HKUnit.count().unitDivided(by: .minute()))
            case HKQuantityType(.activeEnergyBurned):
                energy = statistics.sumQuantity()?.doubleValue(for: .kilocalorie())
            default:
                break
            }
        }
        let now = Date()
        let values = (distance: distance, heartRate: heartRate, energy: energy)
        Task { @MainActor in
            self.collected(distance: values.distance, heartRate: values.heartRate, energy: values.energy, at: now)
        }
    }
}

extension WorkoutManager: CLLocationManagerDelegate {
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        Task { @MainActor in
            self.received(locations: locations)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {}
}
