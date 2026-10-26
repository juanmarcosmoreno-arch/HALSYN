import Foundation

/// Periodo de las estadísticas de carrera.
public enum StatsPeriod: String, CaseIterable, Identifiable, Sendable {
    case week
    case month
    case year

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .week: "Semana"
        case .month: "Mes"
        case .year: "Año"
        }
    }

    var component: Calendar.Component {
        switch self {
        case .week: .weekOfYear
        case .month: .month
        case .year: .year
        }
    }
}

/// Totales de un conjunto de carreras.
public struct RunningTotals: Hashable, Sendable {
    public let count: Int
    /// Metros.
    public let distance: Double
    /// Segundos.
    public let duration: TimeInterval
    /// Ritmo medio ponderado por distancia (tiempo total / distancia total).
    public let averagePace: Pace?
    /// FC media ponderada por la duración de cada carrera.
    public let averageHeartRate: Double?
    /// Desnivel positivo sumado de los entrenamientos que lo guardaron; `nil` si ninguno.
    public let elevationGain: Double?
    /// Potencia media ponderada por duración (solo salidas con medidor).
    public let averagePower: Double?

    /// Velocidad media (misma base que el ritmo medio): la referencia en bici.
    public var averageSpeed: Speed? { Speed(pace: averagePace) }

    public init(_ runs: [WorkoutSummary]) {
        count = runs.count
        distance = runs.compactMap(\.distanceMeters).reduce(0, +)
        duration = runs.map(\.duration).reduce(0, +)
        let measured = runs.filter { ($0.distanceMeters ?? 0) > 0 }
        averagePace = Pace(distanceMeters: measured.compactMap(\.distanceMeters).reduce(0, +), duration: measured.map(\.duration).reduce(0, +))
        let withHeartRate = runs.compactMap { run in run.averageHeartRate.map { ($0, run.duration) } }
        let weight = withHeartRate.map(\.1).reduce(0, +)
        averageHeartRate = weight > 0 ? withHeartRate.map { $0.0 * $0.1 }.reduce(0, +) / weight : nil
        let gains = runs.compactMap(\.elevationGain)
        elevationGain = gains.isEmpty ? nil : gains.reduce(0, +)
        let withPower = runs.compactMap { run in run.averagePower.map { ($0, run.duration) } }
        let powerWeight = withPower.map(\.1).reduce(0, +)
        averagePower = powerWeight > 0 ? withPower.map { $0.0 * $0.1 }.reduce(0, +) / powerWeight : nil
    }
}

/// Kilómetros de una semana o un mes, para el gráfico.
public struct StatsBucket: Hashable, Identifiable, Sendable {
    public let start: Date
    public let distance: Double
    public let isCurrent: Bool
    public var id: Date { start }
}

/// Mejores marcas entre las carreras cargadas.
public struct RunningRecords: Hashable, Sendable {
    public let longest: WorkoutSummary?
    /// Mejor ritmo medio (o velocidad) en entrenamientos de al menos
    /// `RunningStatsBuilder.fastestMinimumDistance(for:)`.
    public let fastest: WorkoutSummary?
    /// Semana (lunes) con más kilómetros y su distancia.
    public let biggestWeek: StatsBucket?
    /// Mayor desnivel positivo en un solo entrenamiento.
    public let mostClimbing: WorkoutSummary?
}

public struct RunningStats: Hashable, Sendable {
    public let period: StatsPeriod
    /// Desde el inicio del periodo actual hasta hoy.
    public let current: RunningTotals
    /// El periodo anterior hasta el mismo punto (p. ej. la semana pasada de
    /// lunes a jueves si hoy es jueves): una comparación justa a mitad de periodo.
    public let previousToDate: RunningTotals
    public let buckets: [StatsBucket]
    public let records: RunningRecords
}

/// Estadísticas de SPRING (solo carreras, no caminatas) y de CYKEL (solo bici).
public enum RunningStatsBuilder {
    public static let bucketCount = 12
    public static let fastestMinimumDistance: Double = 5000

    /// 5 km corriendo; 20 km en bici.
    public static func fastestMinimumDistance(for sport: WorkoutSport) -> Double {
        sport == .cycling ? 20_000 : fastestMinimumDistance
    }

    public static func build(runs allWorkouts: [WorkoutSummary], period: StatsPeriod, today: Date, calendar: Calendar, sport: WorkoutSport = .running) -> RunningStats {
        let runs = allWorkouts.filter { $0.activity.sport == sport && $0.start <= today }
        let currentStart = calendar.dateInterval(of: period.component, for: today)?.start ?? calendar.startOfDay(for: today)
        let previousStart = calendar.date(byAdding: period.component, value: -1, to: currentStart) ?? currentStart
        // Mismo tiempo transcurrido en el periodo anterior.
        let elapsed = today.timeIntervalSince(currentStart)
        let previousEnd = min(previousStart.addingTimeInterval(elapsed), currentStart)

        let current = RunningTotals(runs.filter { $0.start >= currentStart && $0.start <= today })
        let previous = RunningTotals(runs.filter { $0.start >= previousStart && $0.start < previousEnd })

        // Semana y mes: 12 semanas. Año: 12 meses.
        let bucketComponent: Calendar.Component = period == .year ? .month : .weekOfYear
        let bucketStart = calendar.dateInterval(of: bucketComponent, for: today)?.start ?? currentStart
        let buckets: [StatsBucket] = (0..<bucketCount).reversed().compactMap { offset in
            guard let start = calendar.date(byAdding: bucketComponent, value: -offset, to: bucketStart),
                  let end = calendar.date(byAdding: bucketComponent, value: 1, to: start) else { return nil }
            let distance = runs.filter { $0.start >= start && $0.start < end }.compactMap(\.distanceMeters).reduce(0, +)
            return StatsBucket(start: start, distance: distance, isCurrent: offset == 0)
        }

        let longest = runs.filter { ($0.distanceMeters ?? 0) > 0 }.max { ($0.distanceMeters ?? 0) < ($1.distanceMeters ?? 0) }
        let fastest = runs
            .filter { ($0.distanceMeters ?? 0) >= fastestMinimumDistance(for: sport) }
            .compactMap { run in run.averagePace.map { (run, $0) } }
            .min { $0.1.secondsPerKilometer < $1.1.secondsPerKilometer }?.0
        var weeks: [Date: Double] = [:]
        for run in runs {
            guard let start = calendar.dateInterval(of: .weekOfYear, for: run.start)?.start else { continue }
            weeks[start, default: 0] += run.distanceMeters ?? 0
        }
        let biggest = weeks.filter { $0.value > 0 }.max { $0.value < $1.value }.map { StatsBucket(start: $0.key, distance: $0.value, isCurrent: false) }
        let climbing = runs.filter { ($0.elevationGain ?? 0) > 0 }.max { ($0.elevationGain ?? 0) < ($1.elevationGain ?? 0) }

        return RunningStats(
            period: period, current: current, previousToDate: previous, buckets: buckets,
            records: RunningRecords(longest: longest, fastest: fastest, biggestWeek: biggest, mostClimbing: climbing)
        )
    }
}
