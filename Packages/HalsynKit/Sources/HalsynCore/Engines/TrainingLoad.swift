import Foundation

/// Con qué se mide la carga de cada entrenamiento.
public enum LoadMetric: String, CaseIterable, Identifiable, Codable, Sendable {
    /// TRIMP de Banister: duración × intensidad relativa por pulso. Sirve para
    /// correr, caminar y pedalear con solo la FC del reloj.
    case heartRate
    /// TSS de Coggan: solo salidas en bici con medidor de potencia y FTP.
    case power

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .heartRate: "Pulso"
        case .power: "Potencia"
        }
    }
}

/// Carga de un entrenamiento terminado.
public struct WorkoutLoad: Hashable, Sendable {
    /// De dónde sale la carga (de más a menos precisa).
    public enum Source: String, Hashable, Sendable {
        /// Muestras de FC de toda la sesión.
        case heartRateSamples
        /// FC media de la sesión.
        case averageHeartRate
        /// Sin FC: estimada por el ritmo frente a tu ritmo umbral (aproximada).
        case pace
        /// Potencia (TSS).
        case power
    }

    public let workoutID: UUID
    public let date: Date
    public let sport: WorkoutSport
    public let value: Double
    public let source: Source
    /// Minutos de la sesión (para la intensidad media por semana).
    public let minutes: Double

    public init(workoutID: UUID, date: Date, sport: WorkoutSport, value: Double, source: Source = .averageHeartRate, minutes: Double = 0) {
        self.workoutID = workoutID
        self.date = date
        self.sport = sport
        self.value = value
        self.source = source
        self.minutes = minutes
    }

    public var isApproximate: Bool { source == .pace }
}

/// TRIMP de Banister con la FC media de la sesión (Banister, Morton y
/// Fitz-Clarke 1992, apéndice, ec. 1):
/// minutos × x × e^(b·x), con x = (FC media − FC reposo) / (FC máx − FC reposo);
/// b = 1,92 en hombres y 1,67 en mujeres. Sin sexo conocido se usa la media de
/// las dos curvas (y la interfaz lo dice).
public enum BanisterTRIMP {
    public static func weight(_ ratio: Double, sex: ReferenceSex?) -> Double {
        let male = exp(1.92 * ratio)
        let female = exp(1.67 * ratio)
        switch sex {
        case .male: return male
        case .female: return female
        case nil: return (male + female) / 2
        }
    }

    /// `nil` sin FC media o con FC máxima y en reposo incoherentes.
    public static func load(duration: TimeInterval, averageHeartRate: Double?, restingHeartRate: Double, maxHeartRate: Double, sex: ReferenceSex?) -> Double? {
        guard let average = averageHeartRate, average > 0, duration > 0,
              HeartRateZoneConfiguration.plausibleRestingRange.contains(restingHeartRate),
              HeartRateZoneConfiguration.plausibleMaxRange.contains(maxHeartRate),
              maxHeartRate - restingHeartRate >= 30 else { return nil }
        let ratio = min(max((average - restingHeartRate) / (maxHeartRate - restingHeartRate), 0), 1)
        return duration / 60 * ratio * weight(ratio, sex: sex)
    }

    /// TRIMP sumando cada tramo entre lecturas de FC (más fiel que la media en
    /// sesiones con cambios de ritmo). Cada lectura cuenta hasta la siguiente,
    /// con un máximo de 15 s (si el sensor se calla no se extrapola).
    /// `nil` con menos de 10 lecturas o con FC de referencia incoherentes.
    public static func load(samples: [HeartRatePoint], restingHeartRate: Double, maxHeartRate: Double, sex: ReferenceSex?) -> Double? {
        guard samples.count >= 10,
              HeartRateZoneConfiguration.plausibleRestingRange.contains(restingHeartRate),
              HeartRateZoneConfiguration.plausibleMaxRange.contains(maxHeartRate),
              maxHeartRate - restingHeartRate >= 30 else { return nil }
        let sorted = samples.sorted { $0.date < $1.date }
        var total = 0.0
        for (current, next) in zip(sorted, sorted.dropFirst()) {
            let minutes = min(max(next.date.timeIntervalSince(current.date), 0), ZoneTimeAccumulator.maximumGap) / 60
            let ratio = min(max((current.bpm - restingHeartRate) / (maxHeartRate - restingHeartRate), 0), 1)
            total += minutes * ratio * weight(ratio, sex: sex)
        }
        return total
    }

    /// Carga aproximada sin FC, por el ritmo: la intensidad se estima como
    /// 0,85 × (ritmo umbral / ritmo de la sesión), acotada a 0,3…1 (en el umbral
    /// la FC suele rondar el 85 % de la reserva). Misma escala que el TRIMP,
    /// pero menos precisa: se marca como aproximada.
    public static func load(duration: TimeInterval, pace: Double, thresholdPace: Double, sex: ReferenceSex?) -> Double? {
        guard duration > 0, pace > 0, thresholdPace > 0 else { return nil }
        let ratio = min(max(0.85 * thresholdPace / pace, 0.3), 1)
        return duration / 60 * ratio * weight(ratio, sex: sex)
    }
}

/// Monotonía y strain de Foster (1998): con la carga de cada uno de los
/// últimos 7 días (los días sin entrenar cuentan como 0),
/// monotonía = media / desviación típica; strain = carga semanal × monotonía.
/// Una monotonía alta indica días muy parecidos entre sí (poca alternancia de
/// días duros y suaves). Es una descripción del entrenamiento, no un
/// predictor validado de lesiones.
public struct TrainingMonotony: Hashable, Sendable {
    public let weeklyLoad: Double
    public let monotony: Double
    public let strain: Double

    /// Por encima de esto, la semana tuvo poca variación (umbral orientativo de Foster).
    public static let highMonotony = 2.0

    public static func compute(loads: [WorkoutLoad], endingOn today: Date, calendar: Calendar) -> TrainingMonotony? {
        let todayStart = calendar.startOfDay(for: today)
        let daily: [Double] = (0..<7).map { offset in
            guard let day = calendar.date(byAdding: .day, value: -offset, to: todayStart),
                  let next = calendar.date(byAdding: .day, value: 1, to: day) else { return 0 }
            return loads.filter { $0.date >= day && $0.date < next }.map(\.value).reduce(0, +)
        }
        let total = daily.reduce(0, +)
        guard total > 0, daily.filter({ $0 > 0 }).count >= 2 else { return nil }
        let mean = total / 7
        let variance = daily.map { pow($0 - mean, 2) }.reduce(0, +) / 7
        let deviation = variance.squareRoot()
        guard deviation > 0 else { return nil }
        let monotony = mean / deviation
        return TrainingMonotony(weeklyLoad: total, monotony: monotony, strain: total * monotony)
    }
}

/// Datos personales para la carga por pulso.
public struct HeartRateLoadInputs: Hashable, Sendable {
    public var restingHeartRate: Double?
    /// FC máxima de cada deporte (la de bici puede ser distinta).
    public var maxHeartRate: [WorkoutSport: Double]
    public var sex: ReferenceSex?

    public init(restingHeartRate: Double?, maxHeartRate: [WorkoutSport: Double], sex: ReferenceSex?) {
        self.restingHeartRate = restingHeartRate
        self.maxHeartRate = maxHeartRate
        self.sex = sex
    }

    /// FC máxima para un deporte: la suya o, si no hay, la de correr (o la de bici
    /// para quien solo pedalea).
    public func max(for sport: WorkoutSport) -> Double? {
        maxHeartRate[sport] ?? maxHeartRate[.running] ?? maxHeartRate[.cycling]
    }
}

public enum TrainingLoadCalculator {
    /// TRIMP de cada entrenamiento con FC media. Los que no la tienen no suman (se cuentan aparte).
    /// - Con muestras de FC de la sesión: TRIMP por tramos.
    /// - Si no, con FC media: TRIMP de la media.
    /// - Carreras sin FC y con `thresholdPace`: carga aproximada por ritmo.
    /// - El resto no suma (se cuenta aparte).
    public static func heartRateLoads(_ workouts: [WorkoutSummary], inputs: HeartRateLoadInputs, samples: [UUID: [HeartRatePoint]] = [:], thresholdPace: Double? = nil) -> (loads: [WorkoutLoad], skipped: Int) {
        var loads: [WorkoutLoad] = []
        var skipped = 0
        for workout in workouts {
            let minutes = workout.duration / 60
            let sport = workout.activity.sport
            if let resting = inputs.restingHeartRate, let max = inputs.max(for: sport) {
                if let points = samples[workout.id],
                   let value = BanisterTRIMP.load(samples: points, restingHeartRate: resting, maxHeartRate: max, sex: inputs.sex) {
                    loads.append(WorkoutLoad(workoutID: workout.id, date: workout.start, sport: sport, value: value, source: .heartRateSamples, minutes: minutes))
                    continue
                }
                if let value = BanisterTRIMP.load(duration: workout.duration, averageHeartRate: workout.averageHeartRate, restingHeartRate: resting, maxHeartRate: max, sex: inputs.sex) {
                    loads.append(WorkoutLoad(workoutID: workout.id, date: workout.start, sport: sport, value: value, source: .averageHeartRate, minutes: minutes))
                    continue
                }
            }
            if workout.activity.isRun, workout.averageHeartRate == nil, let thresholdPace,
               let pace = workout.averagePace?.secondsPerKilometer,
               let value = BanisterTRIMP.load(duration: workout.duration, pace: pace, thresholdPace: thresholdPace, sex: inputs.sex) {
                loads.append(WorkoutLoad(workoutID: workout.id, date: workout.start, sport: sport, value: value, source: .pace, minutes: minutes))
                continue
            }
            skipped += 1
        }
        return (loads, skipped)
    }
}

/// Forma física, fatiga y frescura de un día, como en el Performance Management
/// Chart de Coggan (medias exponenciales normalizadas, inspiradas en el modelo
/// de impulso-respuesta de Banister): en estado estable valen la carga diaria.
public struct FitnessFatiguePoint: Hashable, Identifiable, Sendable {
    public let day: Date
    /// Carga del día.
    public let load: Double
    /// Media exponencial de 42 días ("CTL").
    public let fitness: Double
    /// Media exponencial de 7 días ("ATL").
    public let fatigue: Double

    public var id: Date { day }
    /// Frescura ("TSB"): forma − fatiga del día anterior (antes de entrenar hoy).
    public let form: Double
}

public enum PerformanceModel {
    public static let fitnessDays: Double = 42
    public static let fatigueDays: Double = 7

    /// Un punto por día desde `start` hasta `end` (incluidos). Cada día:
    /// valor = valor de ayer + (carga de hoy − valor de ayer) / constante.
    /// Empieza en 0: con menos de unas 6 semanas de historia la forma sale baja.
    public static func series(loads: [WorkoutLoad], from start: Date, through end: Date, calendar: Calendar) -> [FitnessFatiguePoint] {
        var daily: [Date: Double] = [:]
        for load in loads {
            daily[calendar.startOfDay(for: load.date), default: 0] += load.value
        }
        var points: [FitnessFatiguePoint] = []
        var fitness = 0.0, fatigue = 0.0
        var day = calendar.startOfDay(for: start)
        let last = calendar.startOfDay(for: end)
        while day <= last {
            let load = daily[day] ?? 0
            let form = fitness - fatigue
            fitness += (load - fitness) / fitnessDays
            fatigue += (load - fatigue) / fatigueDays
            points.append(FitnessFatiguePoint(day: day, load: load, fitness: fitness, fatigue: fatigue, form: form))
            // startOfDay en cada paso: donde el cambio de hora es a medianoche
            // (Chile, Cuba…) el día empieza a la 01:00 y no se arrastra esa hora.
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = calendar.startOfDay(for: next)
        }
        return points
    }
}

/// Carga de una semana (lunes a domingo), por deporte.
public struct WeeklyLoad: Hashable, Identifiable, Sendable {
    public let start: Date
    public let bySport: [WorkoutSport: Double]
    public let isCurrent: Bool

    public var id: Date { start }
    public var total: Double { bySport.values.reduce(0, +) }
}

public struct TrainingLoadSummary: Hashable, Sendable {
    public let metric: LoadMetric
    /// 12 semanas; la última es la actual (hasta hoy).
    public let weeks: [WeeklyLoad]
    /// Carga de los últimos 7 días (incluido hoy).
    public let last7Days: Double
    /// Media semanal de los 28 días anteriores a esos 7; `nil` sin historia suficiente.
    public let previousWeeklyAverage: Double?
    /// Últimos 90 días del modelo de forma y fatiga.
    public let points: [FitnessFatiguePoint]
    /// Días desde el primer entrenamiento con carga.
    public let historyDays: Int
    /// Entrenamientos del periodo que no suman (sin FC media o sin potencia).
    public let skipped: Int
    /// Monotonía y strain de los últimos 7 días (Foster).
    public let monotony: TrainingMonotony?
    /// Entrenamientos de los últimos 28 días con carga aproximada (por ritmo).
    public let approximateCount: Int
    /// Entrenamientos de los últimos 28 días con carga por muestras de FC.
    public let sampledCount: Int

    public var today: FitnessFatiguePoint? { points.last }
    /// Días de historia para que la forma (media de 42 días que empieza en 0)
    /// llegue a cerca del 90 por ciento de su valor estable.
    public static let settledHistoryDays = 90
    /// La forma física aún se está construyendo: sale baja y la frescura, negativa.
    public var isBuildingUp: Bool { historyDays < Self.settledHistoryDays }

    /// Últimos 7 días frente a la media semanal anterior (1 = igual).
    public var ratio: Double? {
        guard let previousWeeklyAverage, previousWeeklyAverage > 0 else { return nil }
        return last7Days / previousWeeklyAverage
    }
}

public enum TrainingLoadBuilder {
    public static let weekCount = 12
    public static let chartDays = 90
    /// Historia que se usa para el modelo (la forma necesita más de 42 días).
    public static let historyLimitDays = 180

    public static func build(loads allLoads: [WorkoutLoad], metric: LoadMetric, skipped: Int, today: Date, calendar: Calendar) -> TrainingLoadSummary {
        let todayStart = calendar.startOfDay(for: today)
        let limit = calendar.date(byAdding: .day, value: -historyLimitDays, to: todayStart) ?? todayStart
        let loads = allLoads.filter { $0.date >= limit && $0.date <= today }
        let firstDay = loads.map { calendar.startOfDay(for: $0.date) }.min()
        let historyDays = firstDay.flatMap { calendar.dateComponents([.day], from: $0, to: todayStart).day.map { $0 + 1 } } ?? 0

        // Semanas de calendario.
        let currentWeek = calendar.dateInterval(of: .weekOfYear, for: today)?.start ?? todayStart
        let weeks: [WeeklyLoad] = (0..<weekCount).reversed().compactMap { offset in
            guard let start = calendar.date(byAdding: .weekOfYear, value: -offset, to: currentWeek),
                  let end = calendar.date(byAdding: .weekOfYear, value: 1, to: start) else { return nil }
            var bySport: [WorkoutSport: Double] = [:]
            for load in loads where load.date >= start && load.date < end {
                bySport[load.sport, default: 0] += load.value
            }
            return WeeklyLoad(start: start, bySport: bySport, isCurrent: offset == 0)
        }

        // Ventanas móviles: 7 días frente a los 28 anteriores.
        let sevenStart = calendar.date(byAdding: .day, value: -6, to: todayStart) ?? todayStart
        let previousStart = calendar.date(byAdding: .day, value: -28, to: sevenStart) ?? sevenStart
        let last7 = loads.filter { $0.date >= sevenStart }.map(\.value).reduce(0, +)
        let previous = loads.filter { $0.date >= previousStart && $0.date < sevenStart }.map(\.value).reduce(0, +)
        let previousAverage: Double? = historyDays >= 35 ? previous / 4 : nil

        let points: [FitnessFatiguePoint]
        if let firstDay {
            points = Array(PerformanceModel.series(loads: loads, from: firstDay, through: todayStart, calendar: calendar).suffix(chartDays))
        } else {
            points = []
        }
        let recentStart = calendar.date(byAdding: .day, value: -27, to: todayStart) ?? todayStart
        let recent = loads.filter { $0.date >= recentStart }
        return TrainingLoadSummary(
            metric: metric, weeks: weeks, last7Days: last7, previousWeeklyAverage: previousAverage, points: points,
            historyDays: historyDays, skipped: skipped,
            monotony: TrainingMonotony.compute(loads: loads, endingOn: today, calendar: calendar),
            approximateCount: recent.filter(\.isApproximate).count,
            sampledCount: recent.filter { $0.source == .heartRateSamples }.count
        )
    }
}
