import Foundation

/// Tramo de una carrera (por defecto, 200 m) para colorear el mapa y alinear ritmo y FC.
public struct RunSegment: Hashable, Identifiable, Sendable {
    public let index: Int
    /// Distancia acumulada al empezar el tramo.
    public let startDistance: Double
    public let distance: Double
    /// Tiempo en movimiento (sin pausas).
    public let duration: TimeInterval
    /// FC media del tramo, si hay lecturas.
    public let heartRate: Double?
    /// Puntos de la ruta del tramo (incluye el primero del siguiente para que no queden huecos).
    public let points: [LocationSample]

    public var id: Int { index }
    public var pace: Pace? { Pace(distanceMeters: distance, duration: duration) }
}

/// Mitad de una carrera para comparar el principio con el final.
public struct RunHalf: Hashable, Sendable {
    public let distance: Double
    public let duration: TimeInterval
    public let heartRate: Double?

    public var pace: Pace? { Pace(distanceMeters: distance, duration: duration) }

    /// Metros por latido: velocidad (m/min) / FC (lpm). Más alto = más eficiente.
    public var metersPerBeat: Double? {
        guard let heartRate, heartRate > 0, duration > 0 else { return nil }
        return distance / duration * 60 / heartRate
    }
}

/// Lo que se puede decir de una carrera con su ruta y su FC.
public struct RunInsights: Hashable, Sendable {
    public let distance: Double
    public let movingTime: TimeInterval
    public let elevationGain: Double
    public let segments: [RunSegment]
    /// Primera y segunda mitad por tiempo en movimiento, tras el calentamiento.
    public let firstHalf: RunHalf?
    public let secondHalf: RunHalf?
    /// Tiempo excluido al principio como calentamiento.
    public let warmup: TimeInterval

    /// Diferencia de ritmo de la segunda mitad frente a la primera (s/km).
    /// Negativo = segunda mitad más rápida ("negative split").
    public var halfPaceDifference: Double? {
        guard let first = firstHalf?.pace, let second = secondHalf?.pace else { return nil }
        return second.secondsPerKilometer - first.secondsPerKilometer
    }

    /// Deriva cardíaca (desacople ritmo:FC, %): cuánto cae la eficiencia de la
    /// primera a la segunda mitad. Solo con 20 min o más en movimiento y FC en
    /// ambas mitades. Positivo = a igual ritmo, el pulso sube al final.
    public var decoupling: Double? {
        guard movingTime >= RunAnalyzer.minimumDecouplingTime,
              let first = firstHalf?.metersPerBeat, let second = secondHalf?.metersPerBeat, first > 0 else { return nil }
        return (first - second) / first * 100
    }

    /// Metros por latido de toda la carrera (sin calentamiento).
    public var metersPerBeat: Double? {
        guard let first = firstHalf, let second = secondHalf,
              let firstHR = first.heartRate, let secondHR = second.heartRate else { return nil }
        let duration = first.duration + second.duration
        guard duration > 0 else { return nil }
        let heartRate = (firstHR * first.duration + secondHR * second.duration) / duration
        return heartRate > 0 ? (first.distance + second.distance) / duration * 60 / heartRate : nil
    }

    /// Variabilidad del ritmo entre tramos (coeficiente de variación, %).
    public var paceVariability: Double? {
        let paces = segments.filter { $0.distance >= RunAnalyzer.segmentLength * 0.8 }.compactMap { $0.pace?.secondsPerKilometer }
        guard paces.count >= 4 else { return nil }
        let mean = paces.reduce(0, +) / Double(paces.count)
        let variance = paces.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Double(paces.count - 1)
        return mean > 0 ? variance.squareRoot() / mean * 100 : nil
    }
}

/// Esta carrera frente a tus carreras de distancia parecida.
public struct SimilarRunComparison: Hashable, Sendable {
    /// Carreras comparadas (sin contar esta).
    public let count: Int
    public let medianPace: Pace
    public let medianHeartRate: Double?
    /// Puesto por ritmo (1 = la más rápida), contando esta.
    public let paceRank: Int
    /// Puesto por metros por latido (1 = la más eficiente), si hay FC.
    public let efficiencyRank: Int?
    public let efficiencyCount: Int
    /// Diferencia de ritmo frente a la mediana (s/km; negativo = más rápida).
    public let paceDifference: Double
}

/// Análisis de una carrera terminada a partir de la ruta y la FC guardadas.
///
/// - Usa el mismo filtro GPS que en vivo; las pausas (huecos de más de 30 s)
///   no cuentan como tiempo en movimiento.
/// - La deriva cardíaca sigue la idea de "Pa:Hr" (Friel): compara la eficiencia
///   (velocidad / FC) de la primera y la segunda mitad tras el calentamiento.
///   Solo tiene sentido en esfuerzos continuos y regulares.
public enum RunAnalyzer {
    public static let segmentLength: Double = 200
    public static let minimumDecouplingTime: TimeInterval = 20 * 60

    /// Calentamiento excluido: 15 % del tiempo en movimiento, como máximo 10 min.
    public static func warmup(for movingTime: TimeInterval) -> TimeInterval {
        min(600, movingTime * 0.15)
    }

    public static func analyze(route: [LocationSample], heartRate: [HeartRatePoint]) -> RunInsights? {
        let sorted = route.sorted { $0.timestamp < $1.timestamp }
        guard sorted.count > 1 else { return nil }
        let pulse = heartRate.sorted { $0.date < $1.date }

        // Línea de tiempo: (instante, tiempo en movimiento, distancia, punto).
        var gps = GPSDistanceAccumulator()
        var timeline: [(date: Date, moving: TimeInterval, distance: Double, sample: LocationSample)] = []
        var moving: TimeInterval = 0
        var previous: Date?
        for sample in sorted {
            if let previous {
                let gap = sample.timestamp.timeIntervalSince(previous)
                if gap <= gps.configuration.maxGap { moving += max(0, gap) }
            }
            previous = sample.timestamp
            gps.add(sample)
            timeline.append((sample.timestamp, moving, gps.distance, sample))
        }
        guard let last = timeline.last, last.distance >= Pace.minimumDistanceMeters, last.moving > 0 else { return nil }

        // Tramos por distancia.
        var segments: [RunSegment] = []
        var start = 0
        for index in timeline.indices.dropFirst() {
            let isLast = index == timeline.count - 1
            let covered = timeline[index].distance - timeline[start].distance
            guard covered >= segmentLength || isLast else { continue }
            let from = timeline[start]
            let to = timeline[index]
            if covered >= Pace.minimumDistanceMeters {
                segments.append(RunSegment(
                    index: segments.count,
                    startDistance: from.distance,
                    distance: covered,
                    duration: to.moving - from.moving,
                    heartRate: average(pulse, from: from.date, to: to.date),
                    points: timeline[start...index].map(\.sample)
                ))
            }
            start = index
        }

        // Mitades por tiempo en movimiento tras el calentamiento.
        let warmup = warmup(for: last.moving)
        let middle = warmup + (last.moving - warmup) / 2
        func point(at time: TimeInterval) -> (date: Date, moving: TimeInterval, distance: Double, sample: LocationSample) {
            timeline.first { $0.moving >= time } ?? last
        }
        let a = point(at: warmup), b = point(at: middle)
        func half(_ from: (date: Date, moving: TimeInterval, distance: Double, sample: LocationSample), _ to: (date: Date, moving: TimeInterval, distance: Double, sample: LocationSample)) -> RunHalf? {
            let duration = to.moving - from.moving
            guard duration > 60 else { return nil }
            return RunHalf(distance: to.distance - from.distance, duration: duration, heartRate: average(pulse, from: from.date, to: to.date, minimumCount: 10))
        }

        return RunInsights(
            distance: last.distance,
            movingTime: last.moving,
            elevationGain: gps.elevationGain,
            segments: segments,
            firstHalf: half(a, b),
            secondHalf: half(b, last),
            warmup: warmup
        )
    }

    /// FC media entre dos instantes; `nil` con menos de `minimumCount` lecturas.
    static func average(_ samples: [HeartRatePoint], from start: Date, to end: Date, minimumCount: Int = 1) -> Double? {
        let values = samples.filter { $0.date >= start && $0.date <= end }.map(\.bpm)
        guard values.count >= minimumCount, !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    /// Metros por latido de un resumen (distancia / tiempo / FC media).
    public static func metersPerBeat(_ workout: WorkoutSummary) -> Double? {
        guard let distance = workout.distanceMeters, let heartRate = workout.averageHeartRate,
              heartRate > 0, workout.duration > 0 else { return nil }
        return distance / workout.duration * 60 / heartRate
    }

    /// Compara con carreras de distancia parecida (±25 %). Hacen falta al menos 3.
    public static func compare(_ run: WorkoutSummary, with history: [WorkoutSummary], tolerance: Double = 0.25, minimumCount: Int = 3) -> SimilarRunComparison? {
        // Carreras con carreras y caminatas con caminatas.
        guard run.activity.isRun || run.activity == .walk, let distance = run.distanceMeters, distance > 0,
              let pace = run.averagePace else { return nil }
        let similar = history.filter { other in
            guard other.id != run.id, other.start != run.start, other.activity.isRun == run.activity.isRun,
                  other.activity == .walk || other.activity.isRun, let otherDistance = other.distanceMeters else { return false }
            return abs(otherDistance - distance) / distance <= tolerance && other.averagePace != nil
        }
        guard similar.count >= minimumCount else { return nil }
        let paces = similar.compactMap { $0.averagePace?.secondsPerKilometer }.sorted()
        let medianPace = median(paces)
        let heartRates = similar.compactMap(\.averageHeartRate).sorted()
        let paceRank = 1 + paces.filter { $0 < pace.secondsPerKilometer }.count

        var efficiencyRank: Int?
        var efficiencyCount = 0
        if let own = metersPerBeat(run) {
            let others = similar.compactMap(metersPerBeat)
            if others.count >= minimumCount {
                efficiencyRank = 1 + others.filter { $0 > own }.count
                efficiencyCount = others.count + 1
            }
        }
        return SimilarRunComparison(
            count: similar.count,
            medianPace: Pace(secondsPerKilometer: medianPace),
            medianHeartRate: heartRates.isEmpty ? nil : median(heartRates),
            paceRank: paceRank,
            efficiencyRank: efficiencyRank,
            efficiencyCount: efficiencyCount,
            paceDifference: pace.secondsPerKilometer - medianPace
        )
    }

    private static func median(_ sorted: [Double]) -> Double {
        guard !sorted.isEmpty else { return 0 }
        let middle = sorted.count / 2
        return sorted.count.isMultiple(of: 2) ? (sorted[middle - 1] + sorted[middle]) / 2 : sorted[middle]
    }
}
