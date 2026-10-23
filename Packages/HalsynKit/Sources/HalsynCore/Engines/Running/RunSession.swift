import Foundation

// MARK: - Estados de la sesión

/// Fase de un entrenamiento, independiente de HealthKit.
public enum WorkoutPhase: String, Sendable {
    case idle
    case preparing
    case running
    case paused
    case stopping
    case ended
}

public enum WorkoutEvent: String, Sendable {
    case start
    case began
    case pause
    case resume
    case end
    case finished
    case fail
}

/// Máquina de estados del entrenamiento. Rechaza transiciones inválidas
/// (p. ej. pausar algo que no ha empezado o reanudar algo terminado).
public struct WorkoutStateMachine: Sendable {
    public private(set) var phase: WorkoutPhase = .idle

    public init() {}

    /// Aplica el evento. Devuelve `false` si no es válido en la fase actual.
    @discardableResult
    public mutating func handle(_ event: WorkoutEvent) -> Bool {
        let next: WorkoutPhase?
        switch (phase, event) {
        case (.idle, .start), (.ended, .start): next = .preparing
        case (.preparing, .began), (.paused, .resume): next = .running
        case (.running, .pause): next = .paused
        case (.running, .end), (.paused, .end), (.preparing, .end): next = .stopping
        case (.stopping, .finished): next = .ended
        case (.preparing, .fail): next = .idle
        case (.running, .fail), (.paused, .fail), (.stopping, .fail): next = .ended
        default: next = nil
        }
        guard let next else { return false }
        phase = next
        return true
    }

    public var isActive: Bool { phase == .running || phase == .paused }
}

// MARK: - Tiempo activo

/// Tiempo transcurrido sin contar las pausas.
public struct ActiveTimer: Sendable {
    public private(set) var start: Date?
    private var pausedAt: Date?
    private var pausedTotal: TimeInterval = 0

    public init() {}

    public mutating func begin(at date: Date) {
        start = date
        pausedAt = nil
        pausedTotal = 0
    }

    public mutating func pause(at date: Date) {
        guard start != nil, pausedAt == nil else { return }
        pausedAt = date
    }

    public mutating func resume(at date: Date) {
        guard let pausedAt else { return }
        pausedTotal += max(0, date.timeIntervalSince(pausedAt))
        self.pausedAt = nil
    }

    public var isPaused: Bool { pausedAt != nil }

    public func elapsed(at date: Date) -> TimeInterval {
        guard let start else { return 0 }
        let end = pausedAt ?? date
        return max(0, end.timeIntervalSince(start) - pausedTotal)
    }
}

// MARK: - Vueltas

public struct Lap: Hashable, Identifiable, Sendable {
    public enum Trigger: String, Sendable { case automatic, manual }

    public let index: Int
    public let distance: Double
    public let duration: TimeInterval
    public let trigger: Trigger

    public var id: Int { index }
    public var pace: Pace? { Pace(distanceMeters: distance, duration: duration) }
}

/// Vueltas automáticas (cada `autoLapDistance` metros) y manuales.
/// El momento exacto de cruce de una vuelta automática se interpola entre las
/// dos actualizaciones de distancia que la rodean.
public struct LapTracker: Sendable {
    public var autoLapDistance: Double?
    public private(set) var laps: [Lap] = []
    private var lapStartDistance: Double = 0
    private var lapStartElapsed: TimeInterval = 0
    private var previous: (distance: Double, elapsed: TimeInterval) = (0, 0)

    public init(autoLapDistance: Double? = 1000) {
        self.autoLapDistance = autoLapDistance
    }

    /// Actualiza con la distancia total y el tiempo activo. Devuelve las vueltas
    /// automáticas completadas en esta actualización.
    @discardableResult
    public mutating func update(distance: Double, elapsed: TimeInterval) -> [Lap] {
        var completed: [Lap] = []
        if let auto = autoLapDistance, auto > 0 {
            while distance >= lapStartDistance + auto {
                let boundary = lapStartDistance + auto
                let span = distance - previous.distance
                let fraction = span > 0 ? (boundary - previous.distance) / span : 1
                let crossing = previous.elapsed + (elapsed - previous.elapsed) * min(max(fraction, 0), 1)
                let lap = Lap(index: laps.count + 1, distance: auto, duration: crossing - lapStartElapsed, trigger: .automatic)
                laps.append(lap)
                completed.append(lap)
                lapStartDistance = boundary
                lapStartElapsed = crossing
                previous = (boundary, crossing)
            }
        }
        previous = (distance, elapsed)
        return completed
    }

    /// Vuelta manual en el instante actual.
    @discardableResult
    public mutating func markLap(distance: Double, elapsed: TimeInterval) -> Lap {
        let lap = Lap(index: laps.count + 1, distance: distance - lapStartDistance, duration: elapsed - lapStartElapsed, trigger: .manual)
        laps.append(lap)
        lapStartDistance = distance
        lapStartElapsed = elapsed
        previous = (distance, elapsed)
        return lap
    }

    public func currentLap(distance: Double, elapsed: TimeInterval) -> (distance: Double, duration: TimeInterval) {
        (max(0, distance - lapStartDistance), max(0, elapsed - lapStartElapsed))
    }
}

// MARK: - Seguimiento completo

/// Métricas en vivo de una carrera.
public struct RunSnapshot: Hashable, Sendable {
    public var phase: WorkoutPhase = .idle
    public var elapsed: TimeInterval = 0
    public var distance: Double = 0
    public var currentPace: Pace?
    public var averagePace: Pace?
    public var heartRate: Double?
    public var averageHeartRate: Double?
    public var maxHeartRate: Double?
    public var activeEnergy: Double?
    public var elevationGain: Double?
    public var lapDistance: Double = 0
    public var lapDuration: TimeInterval = 0
    public var lapPace: Pace?
    public var laps: [Lap] = []

    public init() {}
}

/// Combina distancia, ritmo, vueltas, tiempo activo y FC de una carrera.
///
/// Fuente de distancia: si HealthKit entrega distancia (`updateDistance`), es la
/// referencia (Apple fusiona GPS y acelerómetro). Si no llega, se usa la del GPS
/// propio (`addLocation`). El ritmo se calcula siempre sobre la misma distancia
/// que se muestra, para que sean coherentes.
public struct RunSessionTracker: Sendable {
    public private(set) var stateMachine = WorkoutStateMachine()
    public private(set) var gps: GPSDistanceAccumulator
    public private(set) var lapTracker: LapTracker
    private var timer = ActiveTimer()
    private var pace = PaceEstimator()
    private var healthKitDistance: Double?
    private var heartRates: (sum: Double, count: Int, max: Double) = (0, 0, 0)
    private var lastHeartRate: Double?
    private var activeEnergy: Double?

    public init(autoLapDistance: Double? = 1000, gpsConfiguration: GPSDistanceAccumulator.Configuration = .init()) {
        gps = GPSDistanceAccumulator(configuration: gpsConfiguration)
        lapTracker = LapTracker(autoLapDistance: autoLapDistance)
    }

    public var phase: WorkoutPhase { stateMachine.phase }

    /// Distancia mostrada: la de HealthKit si existe, si no la del GPS.
    public var distance: Double { healthKitDistance ?? gps.distance }

    // MARK: Estados

    @discardableResult
    public mutating func handle(_ event: WorkoutEvent, at date: Date) -> Bool {
        let wasPaused = stateMachine.phase == .paused
        guard stateMachine.handle(event) else { return false }
        switch event {
        case .began:
            timer.begin(at: date)
        case .pause:
            timer.pause(at: date)
            pace.reset()
            gps.breakSegment()
        case .resume:
            timer.resume(at: date)
            pace.reset()
            gps.breakSegment()
        case .end where wasPaused:
            break
        case .end:
            timer.pause(at: date)
        default:
            break
        }
        return true
    }

    // MARK: Datos

    /// Punto GPS. Devuelve `true` si es fiable (para guardarlo en la ruta).
    @discardableResult
    public mutating func addLocation(_ sample: LocationSample) -> Bool {
        guard stateMachine.phase == .running else { return false }
        let accepted = gps.add(sample)
        if healthKitDistance == nil {
            distanceDidChange(at: sample.timestamp)
        }
        return accepted
    }

    /// Distancia total acumulada que informa HealthKit.
    public mutating func updateDistance(total: Double, at date: Date) {
        guard stateMachine.isActive || stateMachine.phase == .stopping else { return }
        healthKitDistance = max(total, healthKitDistance ?? 0)
        if stateMachine.phase == .running {
            distanceDidChange(at: date)
        }
    }

    public mutating func addHeartRate(_ bpm: Double) {
        guard bpm > 0, bpm < 260 else { return }
        lastHeartRate = bpm
        heartRates.sum += bpm
        heartRates.count += 1
        heartRates.max = max(heartRates.max, bpm)
    }

    public mutating func updateActiveEnergy(total: Double) {
        activeEnergy = total
    }

    /// Vuelta manual.
    @discardableResult
    public mutating func markLap(at date: Date) -> Lap? {
        guard stateMachine.isActive else { return nil }
        return lapTracker.markLap(distance: distance, elapsed: timer.elapsed(at: date))
    }

    /// Vueltas automáticas completadas desde la última llamada.
    public private(set) var pendingAutoLaps: [Lap] = []

    public mutating func consumeAutoLaps() -> [Lap] {
        defer { pendingAutoLaps = [] }
        return pendingAutoLaps
    }

    private mutating func distanceDidChange(at date: Date) {
        let elapsed = timer.elapsed(at: date)
        pace.add(cumulativeDistance: distance, at: date)
        pendingAutoLaps += lapTracker.update(distance: distance, elapsed: elapsed)
    }

    // MARK: Resultado

    public func snapshot(at date: Date) -> RunSnapshot {
        var snapshot = RunSnapshot()
        snapshot.phase = stateMachine.phase
        snapshot.elapsed = timer.elapsed(at: date)
        snapshot.distance = distance
        snapshot.currentPace = stateMachine.phase == .running ? pace.currentPace(at: date) : nil
        snapshot.averagePace = Pace(distanceMeters: distance, duration: snapshot.elapsed)
        snapshot.heartRate = lastHeartRate
        snapshot.averageHeartRate = heartRates.count > 0 ? heartRates.sum / Double(heartRates.count) : nil
        snapshot.maxHeartRate = heartRates.count > 0 ? heartRates.max : nil
        snapshot.activeEnergy = activeEnergy
        snapshot.elevationGain = gps.acceptedCount > 0 ? gps.elevationGain : nil
        let lap = lapTracker.currentLap(distance: distance, elapsed: snapshot.elapsed)
        snapshot.lapDistance = lap.distance
        snapshot.lapDuration = lap.duration
        snapshot.lapPace = Pace(distanceMeters: lap.distance, duration: lap.duration)
        snapshot.laps = lapTracker.laps
        return snapshot
    }
}

// MARK: - Campos de pantalla

extension RunSnapshot {
    /// Valor de un campo de la pantalla del reloj. Los campos que todavía no
    /// tienen dato en vivo (zona, cadencia, potencia, objetivo, intervalo) se
    /// muestran vacíos ("--"): no se inventan.
    public func value(for field: WorkoutFieldKind, unit: UnitSystem = .metric, locale: Locale = .current) -> WorkoutFieldValue {
        switch field {
        case .elapsedTime: WorkoutFieldValue(value: HalsynFormat.duration(elapsed), unit: "")
        case .distance: WorkoutFieldValue(value: HalsynFormat.distance(meters: distance, unit: unit, locale: locale), unit: unit.distanceUnitSymbol)
        case .currentPace: WorkoutFieldValue(value: currentPace?.formatted(in: unit), unit: unit.paceUnitSymbol)
        case .averagePace: WorkoutFieldValue(value: averagePace?.formatted(in: unit), unit: unit.paceUnitSymbol)
        case .heartRate: WorkoutFieldValue(value: heartRate.map { HalsynFormat.integer($0, locale: locale) }, unit: "lpm")
        case .lapTime: WorkoutFieldValue(value: HalsynFormat.duration(lapDuration), unit: "")
        case .lapPace: WorkoutFieldValue(value: lapPace?.formatted(in: unit), unit: unit.paceUnitSymbol)
        case .elevationGain: WorkoutFieldValue(value: elevationGain.map { HalsynFormat.integer($0, locale: locale) }, unit: "m")
        case .heartRateZone, .cadence, .runningPower, .targetPace, .intervalTime: WorkoutFieldValue(value: nil, unit: "")
        }
    }
}
