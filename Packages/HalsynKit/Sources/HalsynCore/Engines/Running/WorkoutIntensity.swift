import Foundation

/// Tipo de entrenamiento según su intensidad.
public enum IntensityClass: Int, CaseIterable, Comparable, Hashable, Sendable {
    /// Sin datos suficientes para clasificarlo.
    case unknown
    case recovery
    case easy
    case moderate
    /// Tempo o umbral: fuerte y sostenido.
    case tempo
    /// Series: el pulso sube y baja varias veces.
    case intervals
    /// Muy intenso: pulso medio ≥ 90 % de la máxima sostenido. Es intensidad
    /// fisiológica, **no** significa que fuera un esfuerzo a tope ni que sirva
    /// para el VDOT (eso lo decide `EffortClassifier.eligibility`).
    case veryHard
    /// Marcado por ti como test.
    case test
    /// Marcado por ti como competición.
    case race

    public static func < (lhs: IntensityClass, rhs: IntensityClass) -> Bool { lhs.rawValue < rhs.rawValue }

    /// Baja (recuperación, suave), moderada o alta (umbral y por encima).
    public var bucket: IntensityBucket? {
        switch self {
        case .unknown: nil
        case .recovery, .easy: .low
        case .moderate: .moderate
        case .tempo, .intervals, .veryHard, .test, .race: .high
        }
    }

    public var title: String {
        switch self {
        case .unknown: "Sin clasificar"
        case .recovery: "Recuperación"
        case .easy: "Rodaje suave"
        case .moderate: "Rodaje moderado"
        case .tempo: "Tempo o umbral"
        case .intervals: "Series"
        case .veryHard: "Muy intenso"
        case .test: "Test"
        case .race: "Competición"
        }
    }
}

public enum IntensityBucket: Int, CaseIterable, Comparable, Hashable, Sendable {
    case low, moderate, high
    public static func < (lhs: IntensityBucket, rhs: IntensityBucket) -> Bool { lhs.rawValue < rhs.rawValue }

    public var title: String {
        switch self {
        case .low: "Suave"
        case .moderate: "Moderado"
        case .high: "Intenso"
        }
    }
}

/// Clasificación de un entrenamiento y con qué se decidió.
public struct WorkoutIntensity: Hashable, Sendable {
    /// Cumplimiento de la intensidad prevista por el plan.
    public enum PlanCompliance: String, Hashable, Sendable {
        /// Sin sesión del plan ese día, o sin datos para comparar.
        case notApplicable
        case asPlanned
        /// Sesión suave (suave, larga o recuperación) hecha a tempo o más.
        case harder
        /// Sesión de calidad (umbral o series) hecha a ritmo suave.
        case easier
    }

    public var planCompliance: PlanCompliance {
        guard let sessionType, kind != .unknown else { return .notApplicable }
        switch sessionType {
        case .easy, .long, .recovery:
            return (kind == .tempo || kind == .intervals || kind == .veryHard) ? .harder : .asPlanned
        case .tempo, .intervals:
            return kind <= .easy ? .easier : .asPlanned
        case .test, .rest:
            return .notApplicable
        }
    }

    /// La sesión del plan era suave (suave, larga o recuperación) y se hizo con
    /// intensidad alta (tempo, series o muy intenso). No cambia el objetivo de la sesión.
    public var harderThanPlanned: Bool { planCompliance == .harder }

    /// Esfuerzo percibido (RPE 1–10) que registraste, si lo hay.
    public var rpe: Int?
    /// Intensidad según tu RPE, aparte de la fisiológica.
    public var perceived: IntensityClass? {
        rpe.map { IntensityClassifier.perceivedClass(Double($0)) }
    }
    /// El pulso y tu percepción difieren en dos niveles o más (calor, cansancio,
    /// sensor…). Se muestran las dos; no se elige una.
    public var perceptionDiffers: Bool {
        guard let perceived, kind != .unknown, ![.test, .race].contains(kind) else { return false }
        let order: [IntensityClass] = [.recovery, .easy, .moderate, .tempo, .veryHard]
        let physiological = kind == .intervals ? IntensityClass.tempo : kind
        guard let a = order.firstIndex(of: physiological), let b = order.firstIndex(of: perceived) else { return false }
        return abs(a - b) >= 2
    }

    public enum Basis: String, Hashable, Sendable {
        /// Lo marcaste tú (test o competición).
        case marked
        /// Pulso medio frente a tu FC máxima (y muestras, para las series).
        case heartRate
        /// Tus zonas personales (reserva cardíaca con tu FC en reposo).
        case personalZones
        /// Ritmo frente a tu ritmo de umbral (sin pulso: aproximado).
        case pace
        /// Esfuerzo percibido (sin pulso).
        case perceivedEffort
        /// Sin datos.
        case none
    }

    public let kind: IntensityClass
    public let basis: Basis
    /// Tipo de sesión: la del plan ese día o la estructura detectada (series).
    public var sessionType: SessionKind?

    public init(kind: IntensityClass, basis: Basis, sessionType: SessionKind? = nil) {
        self.kind = kind
        self.basis = basis
        self.sessionType = sessionType
    }

    /// Sin pulso la clasificación es aproximada.
    public var isApproximate: Bool { basis == .pace || basis == .perceivedEffort }
}

/// Clasifica la intensidad de un entrenamiento con la evidencia disponible.
///
/// Reglas (RUNNING_ENGINE.md, "Intensidad"):
/// 1. Test o competición: lo que marcaste tú.
/// 2. Con pulso fiable (fracción f = FC media / FC máxima):
///    - **Muy intenso**: f ≥ 0,90 sostenido 8 min o más. Es solo intensidad:
///      si además sirve para el VDOT lo decide `EffortClassifier.eligibility`
///      (desnivel, sesión planificada, confirmación…).
///    - **Series**: con muestras de pulso, 3 o más subidas y bajadas de al
///      menos ±4 % de la FC máxima alrededor de la mediana y picos ≥ 85 %; o
///      una sesión de series del plan ese día con f ≥ 0,75.
///    - **Tempo/umbral**: f ≥ 0,87, o FC media ≥ 97 % de tu FC de umbral, ≥ 12 min.
///    - **Moderado**: f ≥ 0,80. **Recuperación**: f < 0,70 y ≤ 45 min.
///      **Suave**: el resto.
/// 3. Sin pulso, con ritmo de umbral (carreras con distancia): ritmo / umbral
///    ≤ 1,03 tempo; ≤ 1,12 moderado; ≤ 1,35 suave; más lento recuperación.
///    Nunca «a tope» ni «series». Marcado como aproximado.
/// 4. Sin pulso ni ritmo, esfuerzo percibido (1–10): ≤ 2 recuperación, ≤ 4
///    suave, ≤ 6 moderado, más tempo. Aproximado.
/// 5. Si tus zonas son por FC de umbral (y la configuraste): zonas de Friel
///    en % de esa FC (< 85 % recuperación o suave, 85–89 suave, 90–94
///    moderado, 95–99 tempo, ≥ 100 muy intenso), en lugar del % de la máxima.
/// Son umbrales prácticos (Seiler; Daniels; Friel), no un diagnóstico.
public enum IntensityClassifier {
    public static let recoveryLimit = 0.70
    public static let recoveryMaxDuration: TimeInterval = 45 * 60
    public static let tempoMinimumDuration: TimeInterval = 12 * 60
    public static let intervalSwing = 0.04
    public static let intervalPeak = 0.85
    public static let intervalMinimumCycles = 3

    public static func classify(
        _ workout: WorkoutSummary,
        maxHeartRate: Double?,
        thresholdHeartRate: Double? = nil,
        thresholdPace: Double? = nil,
        samples: [HeartRatePoint]? = nil,
        perceivedEffort: Double? = nil,
        marked: PerformanceResult.Kind? = nil,
        plannedKind: SessionKind? = nil,
        quality: WorkoutQuality? = nil,
        lactateThreshold: Double? = nil,
        zones: HeartRateZoneConfiguration? = nil
    ) -> WorkoutIntensity {
        var result = physiological(workout, maxHeartRate: maxHeartRate, thresholdHeartRate: thresholdHeartRate, thresholdPace: thresholdPace, samples: samples, perceivedEffort: perceivedEffort, marked: marked, plannedKind: plannedKind, quality: quality, lactateThreshold: lactateThreshold, zones: zones)
        result.rpe = perceivedEffort.map { Int($0.rounded()) }
        if result.kind == .intervals {
            result.sessionType = .intervals
        } else if let marked {
            result.sessionType = marked == .test ? .test : nil
        } else {
            result.sessionType = plannedKind == .rest ? nil : plannedKind
        }
        return result
    }

    static func physiological(
        _ workout: WorkoutSummary,
        maxHeartRate: Double?,
        thresholdHeartRate: Double?,
        thresholdPace: Double?,
        samples: [HeartRatePoint]?,
        perceivedEffort: Double?,
        marked: PerformanceResult.Kind?,
        plannedKind: SessionKind?,
        quality: WorkoutQuality?,
        lactateThreshold: Double? = nil,
        zones: HeartRateZoneConfiguration? = nil
    ) -> WorkoutIntensity {
        switch marked {
        case .test?: return WorkoutIntensity(kind: .test, basis: .marked)
        case .race?: return WorkoutIntensity(kind: .race, basis: .marked)
        case nil: break
        }
        // Zonas por FC de umbral (si elegiste ese método): zonas de Friel para
        // correr, en % de la FC de umbral. < 85 % Z1, 85–89 Z2, 90–94 Z3,
        // 95–99 Z4, ≥ 100 Z5.
        if let lactateThreshold, lactateThreshold > 0, let average = workout.averageHeartRate, average > 0,
           quality?.heartRateUsable != false {
            let fraction = average / lactateThreshold
            if let samples, let maxHeartRate, isIntervalPattern(samples, maxHeartRate: maxHeartRate), workout.duration >= tempoMinimumDuration {
                return WorkoutIntensity(kind: .intervals, basis: .heartRate)
            }
            if plannedKind == .intervals, fraction >= 0.85 { return WorkoutIntensity(kind: .intervals, basis: .heartRate) }
            if fraction >= 1.0, workout.duration >= EffortClassifier.maximalDuration.lowerBound { return WorkoutIntensity(kind: .veryHard, basis: .heartRate) }
            if fraction >= 0.95, workout.duration >= tempoMinimumDuration { return WorkoutIntensity(kind: .tempo, basis: .heartRate) }
            if fraction >= 0.90 { return WorkoutIntensity(kind: .moderate, basis: .heartRate) }
            if fraction < 0.85, workout.duration <= recoveryMaxDuration { return WorkoutIntensity(kind: .recovery, basis: .heartRate) }
            return WorkoutIntensity(kind: .easy, basis: .heartRate)
        }
        // 2. Zonas personales por reserva cardíaca (Karvonen con tu FC en
        //    reposo), si elegiste ese método: Z1 recuperación, Z2 suave,
        //    Z3 moderado, Z4 tempo, Z5 muy intenso.
        if let zones, zones.effectiveMethod == .heartRateReserve, let maxHeartRate, maxHeartRate > 0,
           let average = workout.averageHeartRate, average > 0, quality?.heartRateUsable != false {
            var personal = zones
            personal.maxHeartRate = maxHeartRate
            if let zone = personal.zone(for: average) {
                if let samples, isIntervalPattern(samples, maxHeartRate: maxHeartRate), workout.duration >= tempoMinimumDuration {
                    return WorkoutIntensity(kind: .intervals, basis: .personalZones)
                }
                let kind: IntensityClass
                switch zone {
                case ...1: kind = workout.duration <= recoveryMaxDuration ? .recovery : .easy
                case 2: kind = .easy
                case 3: kind = .moderate
                case 4: kind = workout.duration >= tempoMinimumDuration ? .tempo : .moderate
                default: kind = workout.duration >= EffortClassifier.maximalDuration.lowerBound ? .veryHard : .tempo
                }
                return WorkoutIntensity(kind: kind, basis: .personalZones)
            }
        }
        if let average = workout.averageHeartRate, average > 0, let maxHeartRate, maxHeartRate > 0,
           quality?.heartRateUsable != false {
            let fraction = average / maxHeartRate
            if let samples, isIntervalPattern(samples, maxHeartRate: maxHeartRate), workout.duration >= tempoMinimumDuration {
                return WorkoutIntensity(kind: .intervals, basis: .heartRate)
            }
            if plannedKind == .intervals, fraction >= 0.75 {
                return WorkoutIntensity(kind: .intervals, basis: .heartRate)
            }
            if fraction >= EffortClassifier.maximalLimit, workout.duration >= EffortClassifier.maximalDuration.lowerBound {
                return WorkoutIntensity(kind: .veryHard, basis: .heartRate)
            }
            let aboveThreshold = thresholdHeartRate.map { average >= 0.97 * $0 } ?? false
            if (fraction >= EffortClassifier.hardLimit || aboveThreshold), workout.duration >= tempoMinimumDuration {
                return WorkoutIntensity(kind: .tempo, basis: .heartRate)
            }
            if fraction >= EffortClassifier.easyLimit {
                return WorkoutIntensity(kind: .moderate, basis: .heartRate)
            }
            if fraction < recoveryLimit, workout.duration <= recoveryMaxDuration {
                return WorkoutIntensity(kind: .recovery, basis: .heartRate)
            }
            return WorkoutIntensity(kind: .easy, basis: .heartRate)
        }
        if workout.activity.isRun, let thresholdPace, thresholdPace > 0, let pace = workout.averagePace?.secondsPerKilometer,
           quality?.usableForPerformance != false {
            let ratio = pace / thresholdPace
            let kind: IntensityClass = ratio <= 1.03 ? .tempo : (ratio <= 1.12 ? .moderate : (ratio <= 1.35 ? .easy : .recovery))
            return WorkoutIntensity(kind: kind, basis: .pace)
        }
        if let perceivedEffort {
            return WorkoutIntensity(kind: perceivedClass(perceivedEffort), basis: .perceivedEffort)
        }
        return WorkoutIntensity(kind: .unknown, basis: .none)
    }

    /// RPE 1–10 (escala de Borg CR-10): ≤ 2 recuperación, ≤ 4 suave, ≤ 6
    /// moderado, ≤ 8 tempo, 9–10 muy intenso.
    public static func perceivedClass(_ rpe: Double) -> IntensityClass {
        rpe <= 2 ? .recovery : (rpe <= 4 ? .easy : (rpe <= 6 ? .moderate : (rpe <= 8 ? .tempo : .veryHard)))
    }

    /// Subidas y bajadas del pulso: ciclos alto→bajo con histéresis alrededor de la mediana.
    public static func isIntervalPattern(_ samples: [HeartRatePoint], maxHeartRate: Double) -> Bool {
        let values = samples.sorted { $0.date < $1.date }.map(\.bpm).filter { $0 > 0 }
        guard values.count >= 20, let median = RacePerformanceModel.median(values),
              let peak = values.max(), peak >= intervalPeak * maxHeartRate else { return false }
        let high = median + intervalSwing * maxHeartRate
        let low = median - intervalSwing * maxHeartRate
        var state = 0  // 1 alto, -1 bajo
        var cycles = 0
        for value in values {
            if value >= high {
                state = 1
            } else if value <= low {
                if state == 1 { cycles += 1 }
                state = -1
            }
        }
        return cycles >= intervalMinimumCycles
    }
}

// MARK: - Volumen e intensidad

/// Una semana (lunes a domingo, según el calendario) de entrenamiento.
public struct WeeklyVolume: Hashable, Identifiable, Sendable {
    public let start: Date
    /// Metros corridos.
    public let runDistance: Double
    public let runMinutes: Double
    /// Minutos de carrera por intensidad (las no clasificadas no entran).
    public let minutesByBucket: [IntensityBucket: Double]
    /// Minutos de otras actividades (bici, caminatas, otros).
    public let otherMinutes: Double
    /// Días con carrera.
    public let runDays: Int
    public let isCurrent: Bool

    public var id: Date { start }
}

/// Volumen semanal, tendencias de 4, 8 y 12 semanas, reparto de intensidad,
/// descanso y aumentos bruscos **respecto de tu propio historial**.
///
/// No pretende predecir lesiones: el aviso de aumento compara la semana con
/// tu media de las 4 anteriores y tu variación habitual (desviación típica de
/// las 8 anteriores), con un mínimo de +25 % y +3 km. Es una señal para mirar,
/// no un umbral universal.
public struct TrainingVolumeAnalysis: Hashable, Sendable {
    /// Las 12 semanas completas más recientes y la actual (parcial), de la más antigua a la más nueva.
    public let weeks: [WeeklyVolume]
    /// Media de km por semana completa en las últimas 4, 8 y 12.
    public let average4: Double?
    public let average8: Double?
    public let average12: Double?
    /// Pendiente (Theil–Sen) en metros por semana de las últimas 8 semanas completas.
    public let trendPerWeek: Double?
    /// Última semana completa frente a la media de las 4 anteriores (fracción).
    public let lastWeekChange: Double?
    public let isUnusualIncrease: Bool
    /// Días sin entrenar (ninguna actividad) en los últimos 14 días.
    public let restDaysLast14: Int
    /// Racha más larga de días seguidos entrenando en los últimos 28.
    public let longestStreakLast28: Int
    /// Racha más larga de días intensos seguidos en los últimos 14.
    public let consecutiveHardDays: Int
    /// Reparto de los minutos de carrera clasificados de las últimas 4 semanas.
    public let intensityShare: [IntensityBucket: Double]
    /// Minutos de carrera sin clasificar en las últimas 4 semanas.
    public let unclassifiedMinutes: Double

    /// 12 semanas completas más la actual.
    public static let weekCount = 13

    public static func compute(workouts: [WorkoutSummary], intensities: [UUID: WorkoutIntensity], today: Date, calendar: Calendar) -> TrainingVolumeAnalysis {
        let todayStart = calendar.startOfDay(for: today)
        var mondayComponents = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: todayStart)
        mondayComponents.weekday = calendar.firstWeekday
        let currentStart = calendar.date(from: mondayComponents) ?? todayStart
        let starts = (0..<weekCount).reversed().compactMap { calendar.date(byAdding: .day, value: -7 * $0, to: currentStart) }

        let weeks: [WeeklyVolume] = starts.map { start in
            let end = calendar.date(byAdding: .day, value: 7, to: start) ?? start
            let inWeek = workouts.filter { $0.start >= start && $0.start < end && $0.start <= today }
            let runs = inWeek.filter(\.activity.isRun)
            var buckets: [IntensityBucket: Double] = [:]
            for run in runs {
                if let bucket = intensities[run.id]?.kind.bucket { buckets[bucket, default: 0] += run.duration / 60 }
            }
            return WeeklyVolume(
                start: start,
                runDistance: runs.compactMap(\.distanceMeters).reduce(0, +),
                runMinutes: runs.map(\.duration).reduce(0, +) / 60,
                minutesByBucket: buckets,
                otherMinutes: inWeek.filter { !$0.activity.isRun }.map(\.duration).reduce(0, +) / 60,
                runDays: Set(runs.map { calendar.startOfDay(for: $0.start) }).count,
                isCurrent: start == currentStart
            )
        }
        let complete = weeks.filter { !$0.isCurrent }.map(\.runDistance)
        func average(_ count: Int) -> Double? {
            guard complete.count >= count else { return nil }
            return complete.suffix(count).reduce(0, +) / Double(count)
        }
        var trend: Double?
        let recent = Array(complete.suffix(8))
        if recent.count >= 4 {
            trend = RacePerformanceModel.theilSen(recent.enumerated().map { (x: Double($0.offset), y: $0.element) })
        }
        var change: Double?
        var unusual = false
        if complete.count >= 5, let last = complete.last {
            let previous = complete.dropLast().suffix(4)
            let mean = previous.reduce(0, +) / Double(previous.count)
            if mean > 0 {
                change = last / mean - 1
                let history = Array(complete.dropLast().suffix(8))
                let historyMean = history.reduce(0, +) / Double(history.count)
                let sd = (history.map { ($0 - historyMean) * ($0 - historyMean) }.reduce(0, +) / Double(max(history.count - 1, 1))).squareRoot()
                unusual = last > mean + max(2 * sd, 0.25 * mean) && last - mean >= 3000
            }
        }

        // Días con alguna actividad y días intensos.
        let activeDays = Set(workouts.filter { $0.start <= today }.map { calendar.startOfDay(for: $0.start) })
        let hardDays = Set(workouts.filter { $0.start <= today && intensities[$0.id]?.kind.bucket == .high }.map { calendar.startOfDay(for: $0.start) })
        func days(_ count: Int) -> [Date] {
            (0..<count).reversed().compactMap { calendar.date(byAdding: .day, value: -$0, to: todayStart) }
        }
        func longestRun(_ list: [Date], in set: Set<Date>) -> Int {
            var best = 0, current = 0
            for day in list {
                current = set.contains(day) ? current + 1 : 0
                best = max(best, current)
            }
            return best
        }
        let last14 = days(14)
        let restDays = last14.filter { !activeDays.contains($0) }.count

        let fourWeeks = weeks.suffix(4)
        var share: [IntensityBucket: Double] = [:]
        for week in fourWeeks {
            for (bucket, minutes) in week.minutesByBucket { share[bucket, default: 0] += minutes }
        }
        let classified = share.values.reduce(0, +)
        let unclassified = fourWeeks.map(\.runMinutes).reduce(0, +) - classified
        if classified > 0 { share = share.mapValues { $0 / classified } }

        return TrainingVolumeAnalysis(
            weeks: weeks,
            average4: average(4),
            average8: average(8),
            average12: average(12),
            trendPerWeek: trend,
            lastWeekChange: change,
            isUnusualIncrease: unusual,
            restDaysLast14: restDays,
            longestStreakLast28: longestRun(days(28), in: activeDays),
            consecutiveHardDays: longestRun(last14, in: hardDays),
            intensityShare: share,
            unclassifiedMinutes: max(unclassified, 0)
        )
    }
}
