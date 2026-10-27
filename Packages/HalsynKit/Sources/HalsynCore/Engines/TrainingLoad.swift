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
    public let workoutID: UUID
    public let date: Date
    public let sport: WorkoutSport
    public let value: Double

    public init(workoutID: UUID, date: Date, sport: WorkoutSport, value: Double) {
        self.workoutID = workoutID
        self.date = date
        self.sport = sport
        self.value = value
    }
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

    /// FC máxima para un deporte: la suya o, si no hay, la de correr.
    public func max(for sport: WorkoutSport) -> Double? {
        maxHeartRate[sport] ?? maxHeartRate[.running]
    }
}

public enum TrainingLoadCalculator {
    /// TRIMP de cada entrenamiento con FC media. Los que no la tienen no suman (se cuentan aparte).
    public static func heartRateLoads(_ workouts: [WorkoutSummary], inputs: HeartRateLoadInputs) -> (loads: [WorkoutLoad], skipped: Int) {
        guard let resting = inputs.restingHeartRate else { return ([], workouts.count) }
        var loads: [WorkoutLoad] = []
        var skipped = 0
        for workout in workouts {
            guard let max = inputs.max(for: workout.activity.sport),
                  let value = BanisterTRIMP.load(duration: workout.duration, averageHeartRate: workout.averageHeartRate, restingHeartRate: resting, maxHeartRate: max, sex: inputs.sex) else {
                skipped += 1
                continue
            }
            loads.append(WorkoutLoad(workoutID: workout.id, date: workout.start, sport: workout.activity.sport, value: value))
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
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
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

    public var today: FitnessFatiguePoint? { points.last }
    /// La forma física (42 días) aún se está construyendo.
    public var isBuildingUp: Bool { historyDays < Int(PerformanceModel.fitnessDays) }

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
        return TrainingLoadSummary(metric: metric, weeks: weeks, last7Days: last7, previousWeeklyAverage: previousAverage, points: points, historyDays: historyDays, skipped: skipped)
    }
}
