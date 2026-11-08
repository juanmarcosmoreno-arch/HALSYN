import Foundation

/// Qué se detectó en un entrenamiento antes de usarlo para los cálculos.
public enum WorkoutQualityFlag: Hashable, Sendable {
    /// Mismo entrenamiento importado otra vez (mismo deporte, misma hora,
    /// misma duración y distancia). Se queda el registro con más datos.
    case duplicate(of: UUID)
    /// Se superpone con otro registro del mismo deporte (p. ej. reloj y otra
    /// app grabando a la vez). Se queda el de más datos.
    case overlaps(UUID, otherSource: Bool)
    /// Carrera sin distancia: no sirve para ritmo ni forma.
    case missingDistance
    /// Muy corto (menos de 2 min o de 200 m).
    case tooShort
    /// Ritmo imposible para el deporte (error de GPS o de distancia).
    case implausiblePace
    /// FC media o máxima fuera de lo posible, o media mayor que la máxima.
    case implausibleHeartRate
    /// Cadencia 0: el valor se ignora.
    case zeroCadence
    /// Cadencia fuera de lo posible para correr (< 100 o > 260 pasos/min): se ignora.
    case implausibleCadence

    /// Hace que el registro no cuente para nada (volumen incluido).
    public var removesWorkout: Bool {
        switch self {
        case .duplicate, .overlaps: true
        default: false
        }
    }

    /// Hace que el registro no cuente para la forma, las predicciones y el plan.
    public var blocksPerformance: Bool {
        switch self {
        case .duplicate, .overlaps, .missingDistance, .tooShort, .implausiblePace: true
        case .implausibleHeartRate, .zeroCadence, .implausibleCadence: false
        }
    }
}

/// Calidad de un entrenamiento. Nunca se borra nada: solo se marca y se
/// decide qué cálculos lo usan. El usuario puede forzar usarlo o no.
public struct WorkoutQuality: Hashable, Sendable {
    public enum Level: Int, Comparable, Hashable, Sendable {
        case valid, doubtful, excluded
        public static func < (lhs: Level, rhs: Level) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    public let flags: [WorkoutQualityFlag]

    public init(flags: [WorkoutQualityFlag]) {
        self.flags = flags
    }

    public var level: Level {
        if flags.contains(where: \.removesWorkout) { return .excluded }
        if flags.contains(where: \.blocksPerformance) || flags.contains(.implausibleHeartRate) { return .doubtful }
        return .valid
    }

    /// Sirve para la forma (VDOT), las predicciones y el plan.
    public var usableForPerformance: Bool { !flags.contains(where: \.blocksPerformance) }
    /// Su FC se puede usar (zonas, carga, esfuerzo).
    public var heartRateUsable: Bool { !flags.contains(.implausibleHeartRate) }
    /// Algo que mostrar al usuario (la cadencia 0 sola no merece aviso).
    public var needsReview: Bool { flags.contains { $0 != .zeroCadence && $0 != .implausibleCadence } }
}

/// Control de calidad de los entrenamientos de Apple Health.
///
/// Reglas (documentadas en RUNNING_ENGINE.md):
/// - **Duplicado**: mismo deporte, inicio a ≤ 60 s, duración a ≤ 5 % y
///   distancia a ≤ 3 % (o ambas sin distancia).
/// - **Superposición**: mismo deporte y se pisan más del 50 % del más corto.
/// - En ambos casos se conserva el registro con más datos (distancia, FC,
///   cadencia) y, a igualdad, el que empezó antes.
/// - **Ritmo imposible**: correr más rápido que 2:40 min/km o más lento que
///   20:00 min/km de media; caminar más rápido que 4:00 min/km; bici a más de
///   80 km/h de media.
/// - **FC imposible**: media fuera de 35–225 lpm, máxima por encima de 230 o
///   media mayor que la máxima.
/// - **Muy corto**: menos de 2 minutos o, con distancia, menos de 200 m.
public enum DataQuality {
    public static let duplicateStartTolerance: TimeInterval = 60
    public static let duplicateDurationTolerance = 0.05
    public static let duplicateDistanceTolerance = 0.03
    public static let overlapFraction = 0.5
    public static let fastestRunPace: Double = 160
    public static let slowestRunPace: Double = 1200
    public static let fastestWalkPace: Double = 240
    public static let fastestRideSpeed: Double = 80 / 3.6
    public static let plausibleAverageHeartRate: ClosedRange<Double> = 35...225
    public static let maximumHeartRate: Double = 230
    public static let minimumDuration: TimeInterval = 120
    public static let minimumDistance: Double = 200

    public static func assess(_ workouts: [WorkoutSummary]) -> [UUID: WorkoutQuality] {
        var flags: [UUID: [WorkoutQualityFlag]] = [:]
        for workout in workouts {
            flags[workout.id] = ownFlags(workout)
        }
        // Pares del mismo deporte que se pisan en el tiempo.
        let sorted = workouts.sorted { $0.start < $1.start }
        for (index, first) in sorted.enumerated() {
            for second in sorted[(index + 1)...] {
                if second.start >= first.wallClockEnd { break }
                guard first.activity.sport == second.activity.sport else { continue }
                let (keep, drop) = richness(first) >= richness(second) ? (first, second) : (second, first)
                if isDuplicate(first, second) {
                    flags[drop.id, default: []].append(.duplicate(of: keep.id))
                } else if overlapShare(first, second) > overlapFraction {
                    flags[drop.id, default: []].append(.overlaps(keep.id, otherSource: sourceName(first) != sourceName(second)))
                }
            }
        }
        return flags.mapValues(WorkoutQuality.init)
    }

    /// Sin duplicados ni superposiciones y sin los que el usuario excluyó; los
    /// que el usuario incluyó a mano se quedan aunque estén marcados.
    public static func clean(_ workouts: [WorkoutSummary], excluded: Set<UUID> = [], included: Set<UUID> = []) -> [WorkoutSummary] {
        let quality = assess(workouts)
        return workouts.filter { workout in
            if excluded.contains(workout.id) { return false }
            if included.contains(workout.id) { return true }
            return quality[workout.id]?.level != .excluded
        }
    }

    /// Los que sirven para la forma, las predicciones y el plan.
    public static func forPerformance(_ workouts: [WorkoutSummary], included: Set<UUID> = []) -> [WorkoutSummary] {
        let quality = assess(workouts)
        return workouts.filter { included.contains($0.id) || quality[$0.id]?.usableForPerformance != false }
    }

    // MARK: Reglas

    static func ownFlags(_ workout: WorkoutSummary) -> [WorkoutQualityFlag] {
        var flags: [WorkoutQualityFlag] = []
        let distance = workout.distanceMeters ?? 0
        if workout.activity.isRun && distance <= 0 { flags.append(.missingDistance) }
        if workout.duration < minimumDuration || (distance > 0 && distance < minimumDistance) { flags.append(.tooShort) }
        if distance > 0, workout.duration > 0 {
            let pace = workout.duration / (distance / 1000)
            let speed = distance / workout.duration
            switch workout.activity.sport {
            case .running: if pace < fastestRunPace || pace > slowestRunPace { flags.append(.implausiblePace) }
            case .walking: if pace < fastestWalkPace { flags.append(.implausiblePace) }
            case .cycling: if speed > fastestRideSpeed { flags.append(.implausiblePace) }
            case .other: break
            }
        }
        let average = workout.averageHeartRate, maximum = workout.maxHeartRate
        if let average, !plausibleAverageHeartRate.contains(average) {
            flags.append(.implausibleHeartRate)
        } else if let maximum, maximum > maximumHeartRate {
            flags.append(.implausibleHeartRate)
        } else if let average, let maximum, average > maximum + 1 {
            flags.append(.implausibleHeartRate)
        }
        if workout.averageCadence == 0 {
            flags.append(.zeroCadence)
        } else if workout.activity.isRun, let cadence = workout.averageCadence, cadence < 100 || cadence > 260 {
            flags.append(.implausibleCadence)
        }
        return flags
    }

    static func isDuplicate(_ a: WorkoutSummary, _ b: WorkoutSummary) -> Bool {
        guard abs(a.start.timeIntervalSince(b.start)) <= duplicateStartTolerance else { return false }
        let longer = max(a.duration, b.duration)
        guard longer > 0, abs(a.duration - b.duration) / longer <= duplicateDurationTolerance else { return false }
        switch (a.distanceMeters, b.distanceMeters) {
        case let (x?, y?) where max(x, y) > 0: return abs(x - y) / max(x, y) <= duplicateDistanceTolerance
        case (nil, nil): return true
        default: return (a.distanceMeters ?? 0) == 0 && (b.distanceMeters ?? 0) == 0
        }
    }

    /// Fracción del más corto que se pisa con el otro.
    static func overlapShare(_ a: WorkoutSummary, _ b: WorkoutSummary) -> Double {
        let start = max(a.start, b.start), end = min(a.wallClockEnd, b.wallClockEnd)
        let shared = end.timeIntervalSince(start)
        let shortest = min(a.wallClockEnd.timeIntervalSince(a.start), b.wallClockEnd.timeIntervalSince(b.start))
        guard shared > 0, shortest > 0 else { return 0 }
        return shared / shortest
    }

    /// Cuántos datos tiene (para quedarse con el mejor de dos iguales).
    static func richness(_ workout: WorkoutSummary) -> Int {
        var score = 0
        if (workout.distanceMeters ?? 0) > 0 { score += 4 }
        if workout.averageHeartRate != nil { score += 2 }
        if workout.maxHeartRate != nil { score += 1 }
        if (workout.averageCadence ?? 0) > 0 { score += 1 }
        if workout.elevationGain != nil { score += 1 }
        return score
    }

    static func sourceName(_ workout: WorkoutSummary) -> String? {
        if case let .healthKit(name) = workout.origin { return name }
        return nil
    }
}

/// Qué tan fuerte fue una carrera, sin suponer que un entrenamiento rápido
/// fue a tope.
public enum EffortKind: Int, Comparable, Hashable, Sendable {
    /// Sin FC fiable: no se sabe.
    case unknown
    case easy
    case moderate
    case hard
    /// Tan fuerte como una prueba (FC media alta sostenida en 8–75 min).
    case maximal
    /// Marcada por ti como test.
    case test
    /// Marcada por ti como competición.
    case race

    public static func < (lhs: EffortKind, rhs: EffortKind) -> Bool { lhs.rawValue < rhs.rawValue }

    /// Sirve para estimar la forma como un esfuerzo a tope.
    public var isPerformanceEffort: Bool { self >= .maximal }
}

/// Si un entrenamiento sirve para estimar el VDOT. Es independiente de la
/// intensidad fisiológica (un pulso alto no basta) y del tipo de sesión.
public enum VDOTEligibility: Hashable, Sendable {
    /// Marcado por ti como test o competición: cuenta siempre, también si es más lento.
    case confirmed
    /// Cumple todos los criterios de un esfuerzo a tope, pero no lo confirmaste:
    /// solo puede subir la estimación (un entrenamiento más lento no demuestra
    /// que perdiste forma). Puedes confirmarlo o descartarlo.
    case candidate
    case notEligible(Reason)

    public enum Reason: String, Hashable, Sendable {
        case noHeartRate, lowHeartRate, belowThreshold, duration, distance, treadmill, hilly, plannedEasy, plannedWorkout, rejected, quality
    }

    public var isCandidate: Bool { self == .candidate }
}

/// Clasifica el esfuerzo con la FC media relativa a tu FC máxima.
///
/// - test / carrera: lo que marcaste tú.
/// - Con FC media y FC máxima: < 80 % suave, 80–87 % moderado, ≥ 87 % fuerte;
///   ≥ 90 % sostenido entre 8 y 75 min (distancia ≥ 3 km) se considera un
///   esfuerzo comparable a una prueba. En una prueba de 5–10 km la FC media
///   suele quedar por encima del 90 % de la máxima; en un rodaje, muy por
///   debajo. Son umbrales prácticos, documentados, no un diagnóstico.
/// - Sin FC media fiable o sin FC máxima: `unknown` (no se usa como prueba).
public enum EffortClassifier {
    public static let easyLimit = 0.80
    public static let hardLimit = 0.87
    public static let maximalLimit = 0.90
    public static let maximalDuration: ClosedRange<TimeInterval> = 8 * 60...75 * 60
    public static let maximalMinimumDistance: Double = 3000

    public static func classify(_ workout: WorkoutSummary, maxHeartRate: Double?, marked: PerformanceResult.Kind? = nil, quality: WorkoutQuality? = nil) -> EffortKind {
        switch marked {
        case .test?: return .test
        case .race?: return .race
        case nil: break
        }
        guard let average = workout.averageHeartRate, let maxHeartRate, maxHeartRate > 0,
              quality?.heartRateUsable != false else { return .unknown }
        let fraction = average / maxHeartRate
        if fraction >= maximalLimit, maximalDuration.contains(workout.duration),
           (workout.distanceMeters ?? 0) >= maximalMinimumDistance {
            return .maximal
        }
        if fraction >= hardLimit { return .hard }
        if fraction >= easyLimit { return .moderate }
        return .easy
    }

    /// Desnivel máximo (m por km) para usar un entrenamiento como prueba: en
    /// subida el pulso sube sin que el ritmo lo refleje.
    public static let maximumClimbPerKilometer = 10.0

    /// ¿Sirve para estimar el VDOT? Criterios de candidato (todos):
    /// FC media ≥ 90 % de la máxima de referencia (y ≥ tu FC de umbral si la
    /// pusiste), 8–75 min, ≥ 3 km, al aire libre, ≤ 10 m de desnivel por km,
    /// sin una sesión suave, larga, de recuperación, de umbral o de series
    /// planificada ese día, datos
    /// válidos y no descartado por ti.
    public static func eligibility(_ workout: WorkoutSummary, maxHeartRate: Double?, thresholdHeartRate: Double? = nil, plannedKind: SessionKind? = nil, marked: PerformanceResult.Kind? = nil, rejected: Bool = false, quality: WorkoutQuality? = nil) -> VDOTEligibility {
        if marked != nil { return .confirmed }
        if rejected { return .notEligible(.rejected) }
        if quality?.usableForPerformance == false { return .notEligible(.quality) }
        if workout.activity != .outdoorRun { return .notEligible(.treadmill) }
        let distance = workout.distanceMeters ?? 0
        if distance < maximalMinimumDistance { return .notEligible(.distance) }
        if !maximalDuration.contains(workout.duration) { return .notEligible(.duration) }
        guard let average = workout.averageHeartRate, average > 0, let maxHeartRate, maxHeartRate > 0,
              quality?.heartRateUsable != false else { return .notEligible(.noHeartRate) }
        if average / maxHeartRate < maximalLimit { return .notEligible(.lowHeartRate) }
        if let thresholdHeartRate, average < thresholdHeartRate { return .notEligible(.belowThreshold) }
        if let climb = workout.elevationGain, climb / (distance / 1000) > maximumClimbPerKilometer { return .notEligible(.hilly) }
        if let plannedKind, plannedKind == .easy || plannedKind == .long || plannedKind == .recovery { return .notEligible(.plannedEasy) }
        // Un umbral o unas series planificadas tampoco son una prueba a tope:
        // solo cuentan si las confirmas.
        if let plannedKind, plannedKind == .tempo || plannedKind == .intervals { return .notEligible(.plannedWorkout) }
        return .candidate
    }

    /// FC máxima de referencia: la tuya o la más alta observada, descartando
    /// el pico aislado (se usa la segunda más alta si hay 5 o más carreras).
    /// Sin duplicados ni superposiciones y sin pulso inválido, para que una
    /// reimportación no cambie la referencia (con el pico repetido, la
    /// «segunda más alta» pasaba a ser el mismo pico).
    public static func referenceMaxHeartRate(configured: Double?, runs: [WorkoutSummary]) -> Double? {
        if let configured, HeartRateZoneConfiguration.plausibleMaxRange.contains(configured) { return configured }
        // La validada (repetida en al menos dos sesiones); sin ventana de
        // fecha, para que el resultado no dependa del día en que se calcula.
        let assessment = MaxHeartRateValidator.assess(runs: runs, today: .now, calendar: Calendar(identifier: .gregorian), usesWindow: false)
        if let validated = assessment.validated { return validated }
        let quality = DataQuality.assess(runs)
        let values = runs.filter { quality[$0.id]?.level != .excluded && quality[$0.id]?.heartRateUsable != false }
            .compactMap(\.maxHeartRate)
            .filter { HeartRateZoneConfiguration.plausibleMaxRange.contains($0) }
            .sorted(by: >)
        guard let first = values.first else { return nil }
        return values.count >= 5 ? values[1] : first
    }
}
