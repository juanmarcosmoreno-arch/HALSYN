import CoreLocation
import Foundation
import HalsynCore
import HalsynHealthKit
import HealthKit
import Observation
import WatchKit

/// Gestiona una carrera (SPRING) o una salida en bici (CYKEL) real en el Apple Watch.
///
/// - En bici: distancia de `distanceCycling`, potencia y cadencia de los
///   sensores Bluetooth emparejados con el reloj (si los hay), vuelta
///   automática de bici y sin alertas de ritmo.
/// - `HKWorkoutSession` + `HKLiveWorkoutBuilder`: estado, FC, distancia y energía
///   en vivo; al terminar guarda el entrenamiento en Apple Health (una sola vez:
///   el iPhone nunca escribe entrenamientos, así no hay duplicados).
/// - Core Location + `HKWorkoutRouteBuilder`: ruta GPS en exteriores (solo los
///   puntos que el filtro considera fiables).
/// - `RunSessionTracker` (HalsynCore): ritmo, vueltas, tiempo activo, zonas,
///   intervalos y alertas, probado con trazas sintéticas. Usa los ajustes de
///   SPRING que llegan del iPhone (`RunSettingsStore`).
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
    /// Caminata en lugar de carrera (mismas pantallas y guardado).
    private(set) var isWalking = false
    /// Salida en bici (CYKEL): otras pantallas, otra distancia y sensores de bici.
    private(set) var isCycling = false
    /// Plan de intervalos de la carrera actual (`nil` = libre).
    private(set) var plan: IntervalPlan?
    /// Pantallas de métricas de esta carrera (fijadas al empezar).
    private(set) var screens: [WorkoutScreenProfile] = [.easyRun]
    /// Puntos fiables de la ruta, reducidos para el mapa.
    private(set) var routeCoordinates: [CLLocationCoordinate2D] = []
    /// Último aviso (vuelta, paso de intervalo, alerta) para mostrarlo unos segundos.
    private(set) var banner: Banner?
    /// Cuenta atrás antes de empezar (3, 2, 1); `nil` fuera de ella.
    private(set) var countdown: Int?
    /// Permiso de ubicación (para avisar en SPRING y CYKEL si falta o es "una vez").
    private(set) var locationAuthorization: CLAuthorizationStatus = .notDetermined

    struct Banner: Equatable {
        let id = UUID()
        let title: String
        let detail: String?
        let date: Date
    }
    private(set) var outcome: Outcome?
    private(set) var errorMessage: String?
    /// Resumen congelado al terminar (para la pantalla final).
    private(set) var finalSnapshot: RunSnapshot?

    var phase: WorkoutPhase { tracker.phase }
    var isActive: Bool { phase == .preparing || phase == .running || phase == .paused || phase == .stopping }

    @ObservationIgnored let healthStore = HKHealthStore()
    /// Recuperación del pulso al terminar (opcional, se ofrece al guardar).
    let recoveryMeter: RecoveryMeter
    /// Lecturas de FC de los últimos segundos (para la FC al terminar).
    @ObservationIgnored private var recentHeartRates: [(date: Date, bpm: Double)] = []
    @ObservationIgnored private var measuresRecovery = false
    /// Desde cuándo está en pausa (el ejercicio terminó ahí, no al tocar Terminar).
    @ObservationIgnored private var pausedAt: Date?
    /// Se pidió medir la recuperación pero no había pulso al terminar.
    private(set) var recoverySkipped = false
    /// Con más pausa que esto antes de terminar, la recuperación ya pasó: no se ofrece.
    static let maximumPauseForRecovery: TimeInterval = 45
    @ObservationIgnored private var session: HKWorkoutSession?
    @ObservationIgnored private var builder: HKLiveWorkoutBuilder?
    @ObservationIgnored private var routeBuilder: HKWorkoutRouteBuilder?
    @ObservationIgnored private let locationManager = CLLocationManager()
    @ObservationIgnored private var shouldSave = true
    @ObservationIgnored private var ticker: Task<Void, Never>?
    @ObservationIgnored private var lastRoutePoint: CLLocation?

    private override init() {
        recoveryMeter = RecoveryMeter(healthStore: healthStore)
        super.init()
        locationManager.delegate = self
        locationManager.activityType = .fitness
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.distanceFilter = kCLDistanceFilterNone
        locationAuthorization = locationManager.authorizationStatus
        rememberLocationStatus(locationAuthorization)
        UserDefaults.standard.removeObject(forKey: "halsyn.watch.locationAsked")
    }

    /// El permiso de ubicación se perdió desde la última vez (ver `init`).
    private(set) var locationWasReset = false
    static let locationStatusKey = "halsyn.watch.locationStatus"

    private func rememberLocationStatus(_ status: CLAuthorizationStatus) {
        let defaults = UserDefaults.standard
        let previous = (defaults.object(forKey: Self.locationStatusKey) as? Int).flatMap { CLAuthorizationStatus(rawValue: Int32($0)) }
        guard previous != status else { return }
        // Estaba permitida y vuelve a estar sin decidir: watchOS la olvidó (pasa con
        // «Permitir una vez», al arrancar o al volver de segundo plano).
        if status == .notDetermined, previous == .authorizedWhenInUse || previous == .authorizedAlways {
            locationWasReset = true
            PermissionLog.add("Ubicación: el reloj olvidó el permiso (¿«Permitir una vez»?)")
        }
        defaults.set(Int(status.rawValue), forKey: Self.locationStatusKey)
        // Que el reloj diga la decisión (no el estado inicial sin decidir).
        if status != .notDetermined {
            PermissionLog.add("Ubicación: \(PermissionLog.describe(status))")
        }
    }

    func snapshot(at date: Date) -> RunSnapshot {
        finalSnapshot ?? tracker.snapshot(at: date)
    }

    // MARK: Permisos

    /// Pide permisos de Salud solo si falta alguno por decidir. Se piden de una
    /// vez los de correr y los de bici, los mismos que pide el iPhone (los permisos
    /// son comunes): respondidos en cualquiera de los dos, no se vuelve a preguntar.
    private func requestAuthorization() async throws {
        guard await healthNeedsAuthorization() else { return }
        PermissionLog.add("Salud: se pidió al empezar un entrenamiento")
        try await healthStore.requestAuthorization(toShare: HealthKitTypeCatalog.watchShareTypes, read: HealthKitTypeCatalog.watchReadTypes)
    }

    /// `true` si hay permisos de Salud sin responder (no dice si se negaron:
    /// HealthKit no lo revela para la lectura).
    func healthNeedsAuthorization() async -> Bool {
        let status = try? await healthStore.statusForAuthorizationRequest(toShare: HealthKitTypeCatalog.watchShareTypes, read: HealthKitTypeCatalog.watchReadTypes)
        return status != .unnecessary
    }

    /// Desde la pantalla de permisos, sin entrenamiento en marcha.
    func requestHealthAuthorization() async {
        PermissionLog.add("Salud: se pidió desde Permisos")
        try? await healthStore.requestAuthorization(toShare: HealthKitTypeCatalog.watchShareTypes, read: HealthKitTypeCatalog.watchReadTypes)
    }

    /// La ubicación se pide solo si aún no hay respuesta. Si watchOS la olvida
    /// («Permitir una vez»), SPRING, CYKEL y Permisos lo explican.
    func requestLocationIfNeeded() {
        locationAuthorization = locationManager.authorizationStatus
        rememberLocationStatus(locationAuthorization)
        guard locationAuthorization == .notDetermined else { return }
        PermissionLog.add("Ubicación: se pidió")
        locationManager.requestWhenInUseAuthorization()
    }

    /// Ubicación olvidada y aún sin volver a permitir: se avisa cómo dejarla fija.
    var locationWasAllowedOnce: Bool {
        locationWasReset && locationAuthorization == .notDetermined
    }

    var locationDenied: Bool {
        locationAuthorization == .denied || locationAuthorization == .restricted
    }

    // MARK: Ciclo de vida

    func start(indoor: Bool, walking: Bool = false, plan: IntervalPlan? = nil) async {
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = walking ? .walking : .running
        configuration.locationType = indoor ? .indoor : .outdoor
        await start(configuration: configuration, plan: plan)
    }

    /// Salida en bici (CYKEL), en exterior o en rodillo.
    func startRide(indoor: Bool) async {
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .cycling
        configuration.locationType = indoor ? .indoor : .outdoor
        await start(configuration: configuration)
    }

    /// Inicia con una configuración (también la que envía el iPhone con `startWatchApp`).
    func start(configuration: HKWorkoutConfiguration, plan: IntervalPlan? = nil) async {
        guard !isActive else { return }
        let cycling = configuration.activityType == .cycling
        // Los intervalos son de carrera: en bici no se usan.
        reset(plan: cycling ? nil : plan, cycling: cycling)
        isIndoor = configuration.locationType == .indoor
        isWalking = configuration.activityType == .walking
        tracker.handle(.start, at: .now)
        do {
            try await requestAuthorization()
            let session = try HKWorkoutSession(healthStore: healthStore, configuration: configuration)
            let builder = session.associatedWorkoutBuilder()
            let dataSource = HKLiveWorkoutDataSource(healthStore: healthStore, workoutConfiguration: configuration)
            if cycling {
                // Los sensores Bluetooth emparejados con el reloj se recogen solos;
                // se activan también aquí por si la configuración no los incluye.
                for identifier in [HKQuantityTypeIdentifier.distanceCycling, .cyclingPower, .cyclingCadence, .cyclingSpeed] {
                    dataSource.enableCollection(for: HKQuantityType(identifier), predicate: nil)
                }
            }
            builder.dataSource = dataSource
            session.delegate = self
            builder.delegate = self
            self.session = session
            self.builder = builder

            if !isIndoor {
                routeBuilder = HKWorkoutRouteBuilder(healthStore: healthStore, device: nil)
                requestLocationIfNeeded()
                locationManager.startUpdatingLocation()
            }

            // Cuenta atrás 3-2-1: mientras, los sensores (pulso y GPS) se preparan.
            session.prepare()
            for value in stride(from: 3, through: 1, by: -1) {
                countdown = value
                WKInterfaceDevice.current().play(.click)
                try await Task.sleep(for: .seconds(1))
            }
            countdown = nil

            let start = Date()
            session.startActivity(with: start)
            try await builder.beginCollection(at: start)
            startTicker()
        } catch {
            fail(error)
        }
    }

    /// Recupera una sesión activa tras un cierre inesperado de la app.
    func recover() async {
        do {
            let recovered: HKWorkoutSession? = try await healthStore.recoverActiveWorkoutSession()
            guard let session = recovered else { return }
            // Una medición de recuperación interrumpida no se retoma: se cierra sin guardar.
            if session.workoutConfiguration.activityType == .cooldown {
                session.end()
                return
            }
            // El plan de intervalos no se conserva tras un cierre: la carrera sigue como libre.
            reset(plan: nil, cycling: session.workoutConfiguration.activityType == .cycling)
            let builder = session.associatedWorkoutBuilder()
            session.delegate = self
            builder.delegate = self
            self.session = session
            self.builder = builder
            isIndoor = session.workoutConfiguration.locationType == .indoor
            isWalking = session.workoutConfiguration.activityType == .walking
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
            startTicker()
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
        handleCues()
    }

    /// Se ofrece medir la recuperación al terminar: ajuste del iPhone, pulso en los
    /// últimos segundos de ejercicio y, si está en pausa, que la pausa sea corta.
    var offersRecovery: Bool {
        let stop = pausedAt ?? .now
        guard RunSettingsStore.shared.settings.offersRecovery,
              Date.now.timeIntervalSince(stop) <= Self.maximumPauseForRecovery else { return false }
        return HeartRateRecovery.endHeartRate(recentHeartRates, end: stop) != nil
    }

    /// Termina la carrera. `save == false` la descarta sin escribir en Apple Health.
    /// Con `measureRecovery`, tras guardar se mide cómo baja el pulso.
    func end(save: Bool, measureRecovery: Bool = false) {
        shouldSave = save
        measuresRecovery = save && measureRecovery
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
        recoveryMeter.close()
        reset()
    }

    private func reset(plan: IntervalPlan? = nil, cycling: Bool = false) {
        let settings = RunSettingsStore.shared.settings
        isCycling = cycling
        tracker = cycling
            ? RunSessionTracker(settings: settings.forRide(), gpsConfiguration: .cycling)
            : RunSessionTracker(settings: settings, plan: plan)
        self.plan = plan
        screens = settings.validScreens
        routeCoordinates = []
        lastRoutePoint = nil
        banner = nil
        countdown = nil
        ticker?.cancel()
        ticker = nil
        outcome = nil
        errorMessage = nil
        finalSnapshot = nil
        shouldSave = true
        measuresRecovery = false
        recoverySkipped = false
        pausedAt = nil
        recentHeartRates = []
        session = nil
        builder = nil
        routeBuilder = nil
    }

    private func fail(_ error: Error) {
        ticker?.cancel()
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
                pausedAt = nil
                tracker.handle(.resume, at: date)
                WKInterfaceDevice.current().play(.start)
            }
        case .paused:
            pausedAt = date
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
        ticker?.cancel()
        locationManager.stopUpdatingLocation()
        guard let builder else { return }
        do {
            try await builder.endCollection(at: date)
            if shouldSave {
                // Interior o exterior explícito (HÅLSYN lo usa para distinguir cinta y rodillo)
                // y desnivel positivo medido con el GPS (Salud lo muestra en el entrenamiento).
                var metadata: [String: Any] = [HKMetadataKeyIndoorWorkout: isIndoor]
                if !isIndoor, let gain = tracker.snapshot(at: date).elevationGain, gain > 0 {
                    metadata[HKMetadataKeyElevationAscended] = HKQuantity(unit: .meter(), doubleValue: gain.rounded())
                }
                try? await builder.addMetadata(metadata)
                let workout = try await builder.finishWorkout()
                if let workout, let routeBuilder, !isIndoor {
                    _ = try await routeBuilder.finishRoute(with: workout, metadata: nil)
                }
                outcome = .saved
                // La sesión de la carrera ya terminó: ahora la de recuperación. El
                // ejercicio terminó al pausar (si se pausó) o al terminar; el pulso
                // que llegó después de ese momento ya es parte de la recuperación.
                if measuresRecovery {
                    let stop = pausedAt ?? date
                    if let endHeartRate = HeartRateRecovery.endHeartRate(recentHeartRates, end: stop) {
                        let after = recentHeartRates
                            .filter { $0.date > stop }
                            .map { RecoverySample(elapsed: $0.date.timeIntervalSince(stop), bpm: $0.bpm) }
                        await recoveryMeter.start(endHeartRate: endHeartRate, exerciseEnd: stop, minutes: RunSettingsStore.shared.settings.recoveryDuration, initialSamples: after)
                    } else {
                        recoverySkipped = true
                    }
                }
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

    /// Cada segundo: pasos de intervalos por tiempo y alertas.
    private func startTicker() {
        ticker?.cancel()
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self, !Task.isCancelled else { return }
                self.tracker.tick(at: .now)
                self.handleCues()
            }
        }
    }

    /// Hápticos y aviso en pantalla para cada evento de la carrera.
    private func handleCues() {
        let unit = RunSettingsStore.shared.settings.unitSystem
        let cues = RunSettingsStore.shared.settings.cues
        for cue in tracker.consumeCues() {
            let haptic: WKHapticType
            let title: String
            var detail: String?
            var spoken: String?
            switch cue {
            case let .autoLap(lap):
                haptic = .notification
                title = String(localized: "Vuelta \(lap.index)")
                detail = isCycling
                    ? Speed(pace: lap.pace).map { "\($0.formatted(in: unit)) \(unit.speedUnitSymbol)" }
                    : lap.pace.map { "\($0.formatted(in: unit)) \(unit.paceUnitSymbol)" }
                spoken = lapPhrase(lap, unit: unit)
            case let .intervalStep(progress):
                switch progress.step.kind {
                case .work: haptic = .start
                case .recovery, .cooldown: haptic = .stop
                case .warmup: haptic = .click
                }
                title = Bundle.main.localizedString(forKey: progress.step.kind.title, value: nil, table: nil)
                detail = progress.step.repetition.map { "\($0)/\(plan?.repeats ?? $0)" }
                if !cues.intervals {
                    spoken = nil
                } else if progress.step.kind == .work, let repetition = progress.step.repetition {
                    let total = plan?.repeats ?? repetition
                    spoken = String(localized: "Serie \(repetition) de \(total). ¡Vamos!")
                } else {
                    spoken = title
                }
            case .intervalsCompleted:
                haptic = .success
                title = String(localized: "Intervalos completados")
                spoken = cues.intervals ? title : nil
            case let .alert(alert):
                switch alert {
                case .paceTooFast, .heartRateAboveZone: haptic = .directionDown
                case .paceTooSlow, .heartRateBelowZone: haptic = .directionUp
                case .paceBackInRange, .heartRateBackInZone: haptic = .click
                }
                title = Bundle.main.localizedString(forKey: alert.title, value: nil, table: nil)
                spoken = cues.alerts ? title : nil
            }
            WKInterfaceDevice.current().play(haptic)
            if let spoken { VoiceCoach.shared.say(spoken) }
            banner = Banner(title: title, detail: detail, date: .now)
        }
    }

    /// Lo que dice la voz en una vuelta automática, según lo elegido en Ajustes
    /// (`nil` si esta vuelta no toca o los avisos de vueltas están apagados).
    private func lapPhrase(_ lap: Lap, unit: UnitSystem) -> String? {
        let cues = RunSettingsStore.shared.settings.cues
        let laps = tracker.lapTracker.laps.prefix(lap.index)
        // Solo cuentan las automáticas: una vuelta manual no corre la cuenta.
        let ordinal = laps.filter { $0.trigger == .automatic }.count
        guard cues.speaksLap(ordinal) else { return nil }
        // Distancia real al cerrar la vuelta (con las manuales incluidas).
        let covered = laps.reduce(0) { $0 + $1.distance }
        let lapUnits = Int((lap.distance / unit.metersPerDistanceUnit).rounded())
        let wholeUnits = lapUnits > 0 && abs(lap.distance - Double(lapUnits) * unit.metersPerDistanceUnit) < 1
        let number = wholeUnits ? Int((covered / unit.metersPerDistanceUnit).rounded()) : nil
        let title = CoachPhrases.lapTitle(unitNumber: number, lapNumber: ordinal, unit: unit)
        let snapshot = tracker.snapshot(at: .now)
        if isCycling {
            return CoachPhrases.rideLap(title: title, lapSpeed: Speed(pace: lap.pace), lapUnits: wholeUnits ? lapUnits : 0, averageSpeed: Speed(pace: snapshot.averagePace), heartRate: snapshot.heartRate, elapsed: snapshot.elapsed, unit: unit, cues: cues)
        }
        return CoachPhrases.runLap(title: title, lapPace: lap.pace, averagePace: snapshot.averagePace, heartRate: snapshot.heartRate, elapsed: snapshot.elapsed, unit: unit, cues: cues)
    }

    fileprivate func collected(_ values: CollectedValues, at date: Date) {
        if let distance = isCycling ? values.cyclingDistance : values.distance {
            tracker.updateDistance(total: distance, at: date)
        }
        if let heartRate = values.heartRate {
            tracker.addHeartRate(heartRate, at: date)
            recentHeartRates.append((date, heartRate))
            recentHeartRates.removeAll { date.timeIntervalSince($0.date) > 60 }
        }
        if let energy = values.energy {
            tracker.updateActiveEnergy(total: energy)
        }
        if isCycling {
            if let power = values.cyclingPower {
                tracker.updateCyclingPower(power, average: values.averageCyclingPower, at: date)
            }
            if let cadence = values.cadence {
                tracker.updateCadence(cadence, average: values.averageCadence, at: date)
            }
        } else if let power = values.runningPower {
            tracker.updatePower(power)
        }
        handleCues()
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
        handleCues()
        for location in reliable where lastRoutePoint.map({ location.distance(from: $0) >= 10 }) ?? true {
            routeCoordinates.append(location.coordinate)
            lastRoutePoint = location
        }
        guard !reliable.isEmpty, let routeBuilder else { return }
        let points = reliable
        Task {
            try? await routeBuilder.insertRouteData(points)
        }
    }
}

/// Valores que entrega `HKLiveWorkoutBuilder` en una actualización.
struct CollectedValues: Sendable {
    var distance: Double?
    var cyclingDistance: Double?
    var heartRate: Double?
    var energy: Double?
    var runningPower: Double?
    var cyclingPower: Double?
    var averageCyclingPower: Double?
    var cadence: Double?
    var averageCadence: Double?
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
        var values = CollectedValues()
        let perMinute = HKUnit.count().unitDivided(by: .minute())
        for type in collectedTypes {
            guard let quantityType = type as? HKQuantityType, let statistics = workoutBuilder.statistics(for: quantityType) else { continue }
            switch quantityType {
            case HKQuantityType(.distanceWalkingRunning):
                values.distance = statistics.sumQuantity()?.doubleValue(for: .meter())
            case HKQuantityType(.distanceCycling):
                values.cyclingDistance = statistics.sumQuantity()?.doubleValue(for: .meter())
            case HKQuantityType(.heartRate):
                values.heartRate = statistics.mostRecentQuantity()?.doubleValue(for: perMinute)
            case HKQuantityType(.activeEnergyBurned):
                values.energy = statistics.sumQuantity()?.doubleValue(for: .kilocalorie())
            case HKQuantityType(.runningPower):
                // Solo si el reloj la mide y la entrega en vivo; si no, el campo queda en "--".
                values.runningPower = statistics.mostRecentQuantity()?.doubleValue(for: .watt())
            case HKQuantityType(.cyclingPower):
                // Medidor de potencia Bluetooth emparejado con el reloj.
                values.cyclingPower = statistics.mostRecentQuantity()?.doubleValue(for: .watt())
                values.averageCyclingPower = statistics.averageQuantity()?.doubleValue(for: .watt())
            case HKQuantityType(.cyclingCadence):
                values.cadence = statistics.mostRecentQuantity()?.doubleValue(for: perMinute)
                values.averageCadence = statistics.averageQuantity()?.doubleValue(for: perMinute)
            default:
                break
            }
        }
        let now = Date()
        let collected = values
        Task { @MainActor in
            self.collected(collected, at: now)
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

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            self.locationAuthorization = status
            self.rememberLocationStatus(status)
        }
    }
}
