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
    /// Zona cardíaca actual (0 = por debajo de Z1); `nil` sin FC o sin zonas configuradas.
    public var heartRateZone: Int?
    /// Segundos en cada zona (índice 0 = por debajo de Z1).
    public var zoneSeconds: [TimeInterval] = Array(repeating: 0, count: 6)
    /// Paso actual de los intervalos; `nil` en carrera libre o al terminar el plan.
    public var interval: IntervalProgress?
    public var intervalPlanName: String?
    public var intervalsCompleted = false
    /// Ritmo objetivo vigente (serie actual o alerta de ritmo de carrera libre).
    public var paceTarget: PaceRange?
    /// Potencia en vatios (carrera o medidor de bici), solo si llega en vivo.
    /// En bici es la media de los últimos 3 s, como en los ciclocomputadores.
    public var power: Double?
    /// Potencia media de la sesión (bici, la calcula HealthKit).
    public var averagePower: Double?
    /// Zona de potencia 1…7 (bici, con FTP configurado).
    public var powerZone: Int?
    /// Cadencia de pedaleo en rpm (sensor de cadencia o medidor de potencia).
    public var cadence: Double?
    public var averageCadence: Double?
    /// Ritmo actual (s/km) cada 5 s de tiempo activo, para el gráfico en vivo.
    public var paceSamples: [LiveSample] = []
    /// FC cada 5 s de tiempo activo.
    public var heartRateSamples: [LiveSample] = []

    public init() {}
}

/// Muestra de una serie en vivo (tiempo activo en segundos, valor).
public struct LiveSample: Hashable, Sendable {
    public let elapsed: TimeInterval
    public let value: Double

    public init(elapsed: TimeInterval, value: Double) {
        self.elapsed = elapsed
        self.value = value
    }
}

extension Array where Element == LiveSample {
    /// Media móvil centrada de `window` muestras (suaviza sin desplazar en el tiempo).
    /// No mezcla tramos separados por un hueco mayor que `maxGap` segundos.
    public func smoothed(window: Int = 3, maxGap: TimeInterval = 15) -> [LiveSample] {
        guard window > 1, count > 2 else { return self }
        let half = window / 2
        return indices.map { index in
            var sum = 0.0, n = 0.0
            for j in Swift.max(0, index - half)...Swift.min(count - 1, index + half) {
                guard abs(self[j].elapsed - self[index].elapsed) <= maxGap * Double(half) else { continue }
                sum += self[j].value
                n += 1
            }
            return LiveSample(elapsed: self[index].elapsed, value: sum / n)
        }
    }

    /// Reduce a como mucho `maxPoints` promediando bloques (para dibujar carreras largas).
    public func downsampled(maxPoints: Int) -> [LiveSample] {
        guard maxPoints > 0, count > maxPoints else { return self }
        let size = Int((Double(count) / Double(maxPoints)).rounded(.up))
        return stride(from: 0, to: count, by: size).map { start in
            let block = self[start..<Swift.min(start + size, count)]
            let value = block.map(\.value).reduce(0, +) / Double(block.count)
            let elapsed = block.map(\.elapsed).reduce(0, +) / Double(block.count)
            return LiveSample(elapsed: elapsed, value: value)
        }
    }
}

/// Avisos para el corredor (hápticos en el reloj).
public enum RunCue: Hashable, Sendable {
    case autoLap(Lap)
    case intervalStep(IntervalProgress)
    case intervalsCompleted
    case alert(RunAlert)
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
    private var power: Double?
    private var powerReadings: [(date: Date, watts: Double)] = []
    private var averagePower: Double?
    private var cadence: Double?
    private var cadenceDate: Date?
    private var averageCadence: Double?
    private let ftp: Double?
    private let zones: HeartRateZoneConfiguration
    private var zoneTime = ZoneTimeAccumulator()
    private var currentZone: Int?
    public private(set) var intervals: IntervalTracker?
    private var alerts: RunAlertEngine
    private var freeRunPaceTarget: PaceRange?
    private var intervalsCompleted = false
    private var lastTick: Date?
    private var paceSamples: [LiveSample] = []
    private var heartRateSamples: [LiveSample] = []
    /// Intervalo de muestreo de las series en vivo.
    public static let liveSampleInterval: TimeInterval = 5

    public init(autoLapDistance: Double? = 1000, gpsConfiguration: GPSDistanceAccumulator.Configuration = .init()) {
        self.init(settings: RunSettings(autoLapDistance: autoLapDistance), gpsConfiguration: gpsConfiguration)
    }

    /// - Parameters:
    ///   - settings: vueltas automáticas, zonas y alertas.
    ///   - plan: plan de intervalos; `nil` = carrera libre.
    public init(settings: RunSettings, plan: IntervalPlan? = nil, gpsConfiguration: GPSDistanceAccumulator.Configuration = .init()) {
        gps = GPSDistanceAccumulator(configuration: gpsConfiguration)
        lapTracker = LapTracker(autoLapDistance: settings.autoLapDistance)
        zones = settings.zones
        ftp = settings.validFunctionalThresholdPower
        alerts = RunAlertEngine(configuration: settings.alerts)
        freeRunPaceTarget = settings.alerts.paceEnabled ? settings.alerts.paceRange : nil
        intervals = plan.map(IntervalTracker.init(plan:))
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
            zoneTime.breakSegment(at: date)
            alerts.reset()
        case .resume:
            timer.resume(at: date)
            pace.reset()
            gps.breakSegment()
        case .end where wasPaused:
            break
        case .end:
            timer.pause(at: date)
            zoneTime.breakSegment(at: date)
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

    /// Lectura de FC. Con `date`, cuenta también el tiempo en zonas (solo corriendo).
    public mutating func addHeartRate(_ bpm: Double, at date: Date? = nil) {
        guard bpm > 0, bpm < 260 else { return }
        lastHeartRate = bpm
        heartRates.sum += bpm
        heartRates.count += 1
        heartRates.max = max(heartRates.max, bpm)
        currentZone = zones.zone(for: bpm)
        if let date, stateMachine.phase == .running {
            zoneTime.add(zone: currentZone, at: date)
        }
    }

    /// Potencia de carrera en vatios (si el reloj la mide).
    public mutating func updatePower(_ watts: Double) {
        guard watts > 0, watts < 2000 else { return }
        power = watts
    }

    /// Potencia de un medidor de bici. 0 W es válido (rueda libre). Se muestra
    /// la media de los últimos `powerSmoothing` segundos.
    public mutating func updateCyclingPower(_ watts: Double, average: Double?, at date: Date) {
        guard watts >= 0, watts < 2500 else { return }
        powerReadings.append((date, watts))
        powerReadings.removeAll { date.timeIntervalSince($0.date) > Self.powerSmoothing }
        power = powerReadings.map(\.watts).reduce(0, +) / Double(powerReadings.count)
        if let average, average >= 0, average < 2500 { averagePower = average }
    }

    /// Cadencia de pedaleo en rpm.
    public mutating func updateCadence(_ rpm: Double, average: Double?, at date: Date) {
        guard rpm >= 0, rpm < 250 else { return }
        cadence = rpm
        cadenceDate = date
        if let average, average >= 0, average < 250 { averageCadence = average }
    }

    public static let powerSmoothing: TimeInterval = 3
    /// Sin lecturas nuevas durante este tiempo, potencia y cadencia se muestran vacías.
    public static let sensorTimeout: TimeInterval = 6

    /// Se llama cada segundo: avanza los pasos por tiempo y evalúa las alertas.
    public mutating func tick(at date: Date) {
        guard stateMachine.phase == .running else { return }
        if let last = lastTick, date.timeIntervalSince(last) < 0.5 { return }
        lastTick = date
        recordLiveSamples(at: date)
        advanceIntervals(at: date)
        let alertsNow = alerts.evaluate(
            pace: pace.currentPace(at: date),
            paceTarget: currentPaceTarget,
            zone: lastHeartRate == nil ? nil : currentZone,
            at: date
        )
        pendingCues += alertsNow.map(RunCue.alert)
    }

    /// Guarda ritmo y FC cada `liveSampleInterval` segundos de tiempo activo.
    /// Un hueco sin ritmo (parado) no se rellena: el gráfico muestra el corte.
    private mutating func recordLiveSamples(at date: Date) {
        let elapsed = timer.elapsed(at: date)
        let last = max(paceSamples.last?.elapsed ?? -.infinity, heartRateSamples.last?.elapsed ?? -.infinity)
        guard elapsed - last >= Self.liveSampleInterval else { return }
        if let current = pace.currentPace(at: date) {
            paceSamples.append(LiveSample(elapsed: elapsed, value: current.secondsPerKilometer))
        }
        if let lastHeartRate {
            heartRateSamples.append(LiveSample(elapsed: elapsed, value: lastHeartRate))
        }
    }

    /// Objetivo de ritmo vigente: el de la serie en intervalos, el de la alerta en carrera libre.
    public var currentPaceTarget: PaceRange? {
        if let intervals {
            return intervals.currentStep?.paceTarget
        }
        return freeRunPaceTarget
    }

    public mutating func updateActiveEnergy(total: Double) {
        activeEnergy = total
    }

    /// Vuelta manual. En intervalos, si el paso actual es abierto, además pasa al siguiente.
    @discardableResult
    public mutating func markLap(at date: Date) -> Lap? {
        guard stateMachine.isActive else { return nil }
        let elapsed = timer.elapsed(at: date)
        let total = distance
        if intervals?.currentStep?.goal == .open, let next = intervals?.advance(distance: total, elapsed: elapsed) {
            pendingCues.append(.intervalStep(next))
        }
        checkIntervalsCompleted()
        return lapTracker.markLap(distance: total, elapsed: elapsed)
    }

    /// Vueltas automáticas completadas desde la última llamada.
    public private(set) var pendingAutoLaps: [Lap] = []
    /// Avisos pendientes (vueltas, pasos de intervalos, alertas).
    public private(set) var pendingCues: [RunCue] = []

    public mutating func consumeAutoLaps() -> [Lap] {
        defer { pendingAutoLaps = [] }
        return pendingAutoLaps
    }

    public mutating func consumeCues() -> [RunCue] {
        defer { pendingCues = []; pendingAutoLaps = [] }
        return pendingCues
    }

    private mutating func distanceDidChange(at date: Date) {
        let elapsed = timer.elapsed(at: date)
        pace.add(cumulativeDistance: distance, at: date)
        let laps = lapTracker.update(distance: distance, elapsed: elapsed)
        pendingAutoLaps += laps
        pendingCues += laps.map(RunCue.autoLap)
        advanceIntervals(at: date)
    }

    private mutating func advanceIntervals(at date: Date) {
        guard intervals != nil else { return }
        let total = distance
        let elapsed = timer.elapsed(at: date)
        let started = intervals?.update(distance: total, elapsed: elapsed) ?? []
        pendingCues += started.map(RunCue.intervalStep)
        checkIntervalsCompleted()
    }

    private mutating func checkIntervalsCompleted() {
        guard let intervals, intervals.isFinished, !intervalsCompleted else { return }
        intervalsCompleted = true
        pendingCues.append(.intervalsCompleted)
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
        snapshot.heartRateZone = lastHeartRate == nil ? nil : currentZone
        snapshot.zoneSeconds = zoneTime.seconds
        snapshot.interval = intervals?.progress(elapsed: snapshot.elapsed, distance: distance)
        snapshot.intervalPlanName = intervals?.plan.name
        snapshot.intervalsCompleted = intervalsCompleted
        snapshot.paceTarget = currentPaceTarget
        let powerIsStale = powerReadings.last.map { date.timeIntervalSince($0.date) > Self.sensorTimeout } ?? false
        snapshot.power = powerIsStale ? nil : power
        snapshot.averagePower = averagePower
        snapshot.powerZone = ftp.flatMap { ftp in snapshot.power.flatMap { PowerZones.zone(for: $0, ftp: ftp) } }
        snapshot.cadence = (cadenceDate.map { date.timeIntervalSince($0) > Self.sensorTimeout } ?? false) ? nil : cadence
        snapshot.averageCadence = averageCadence
        snapshot.paceSamples = paceSamples
        snapshot.heartRateSamples = heartRateSamples
        return snapshot
    }
}

// MARK: - Campos de pantalla

extension RunSnapshot {
    /// Valor de un campo de la pantalla del reloj. Los campos sin dato en vivo
    /// (zona sin FC máxima configurada, cadencia, potencia si el reloj no la
    /// mide, objetivo o intervalo en carrera libre) se muestran vacíos ("--"):
    /// no se inventan.
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
        case .heartRateZone: WorkoutFieldValue(value: heartRateZone.map { $0 == 0 ? "<Z1" : "Z\($0)" }, unit: "")
        case .targetPace: WorkoutFieldValue(value: paceTarget?.formatted(in: unit), unit: unit.paceUnitSymbol)
        case .intervalTime: intervalValue(locale: locale)
        case .runningPower: WorkoutFieldValue(value: power.map { HalsynFormat.integer($0, locale: locale) }, unit: "W")
        // La cadencia en vivo no se muestra hasta verificar su disponibilidad en dispositivo.
        case .cadence: WorkoutFieldValue(value: nil, unit: "")
        }
    }

    /// Lo que falta del paso (tiempo o metros); en pasos abiertos, lo que lleva.
    private func intervalValue(locale: Locale) -> WorkoutFieldValue {
        guard let interval else { return WorkoutFieldValue(value: nil, unit: "") }
        switch interval.step.goal {
        case .time: return WorkoutFieldValue(value: HalsynFormat.duration(interval.remaining ?? 0), unit: "")
        case .distance: return WorkoutFieldValue(value: HalsynFormat.integer(interval.remaining ?? 0, locale: locale), unit: "m")
        case .open: return WorkoutFieldValue(value: HalsynFormat.duration(interval.elapsed), unit: "")
        }
    }
}
