import Foundation

/// Categoría de récord personal de carrera.
public enum RunRecordCategory: String, Codable, CaseIterable, Hashable, Identifiable, Sendable {
    case best400
    case best800
    case fastestKilometer
    case bestMile
    case best3K
    case fastest5K
    case fastest10K
    case bestHalf
    case bestMarathon
    case longestDistance
    case longestDuration

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .best400: "400 m más rápidos"
        case .best800: "800 m más rápidos"
        case .fastestKilometer: "Kilómetro más rápido"
        case .bestMile: "Milla más rápida"
        case .best3K: "3 km más rápidos"
        case .fastest5K: "5 km más rápidos"
        case .fastest10K: "10 km más rápidos"
        case .bestHalf: "Media maratón más rápida"
        case .bestMarathon: "Maratón más rápida"
        case .longestDistance: "Distancia más larga"
        case .longestDuration: "Carrera más larga en tiempo"
        }
    }

    /// Distancia del esfuerzo en metros (solo las de tiempo).
    public var effortDistance: Double? {
        switch self {
        case .best400: 400
        case .best800: 800
        case .fastestKilometer: 1000
        case .bestMile: 1609.344
        case .best3K: 3000
        case .fastest5K: 5000
        case .fastest10K: 10_000
        case .bestHalf: 21_097.5
        case .bestMarathon: 42_195
        case .longestDistance, .longestDuration: nil
        }
    }

    /// Mayor es mejor (distancia y duración); en los tiempos, menor.
    public var higherIsBetter: Bool { effortDistance == nil }

    func isBetter(_ a: Double, than b: Double) -> Bool {
        higherIsBetter ? a > b : a < b
    }
}

/// Valores de una carrera para cada categoría (segundos o metros).
public struct RunRecordEntry: Codable, Hashable, Identifiable, Sendable {
    public let id: UUID
    public let date: Date
    public var values: [RunRecordCategory: Double]
    /// Segundo de la carrera en que empieza cada mejor esfuerzo (desde el inicio, con pausas).
    public var starts: [RunRecordCategory: Double]?
    /// Pulso medio de cada mejor esfuerzo, si hay muestras.
    public var heartRates: [RunRecordCategory: Double]?

    public init(id: UUID, date: Date, values: [RunRecordCategory: Double], starts: [RunRecordCategory: Double]? = nil, heartRates: [RunRecordCategory: Double]? = nil) {
        self.id = id
        self.date = date
        self.values = values
        self.starts = starts
        self.heartRates = heartRates
    }
}

/// Un punto de la carrera: segundos desde el inicio (reloj de pared, con
/// pausas) y metros acumulados.
public struct EffortPoint: Hashable, Sendable {
    public let time: TimeInterval
    public let distance: Double

    public init(time: TimeInterval, distance: Double) {
        self.time = time
        self.distance = distance
    }
}

/// Puesto de una carrera en una categoría (1.º, 2.º o 3.º).
public struct RunRecordPlacement: Codable, Hashable, Identifiable, Sendable {
    public let category: RunRecordCategory
    public let rank: Int
    public let value: Double
    /// La mejor marca anterior (para decir cuánto se mejoró).
    public let previousBest: Double?

    public var id: RunRecordCategory { category }
    public var isRecord: Bool { rank == 1 }
}

/// Las 3 mejores marcas de cada categoría y cuántas carreras hay. Viaja del
/// iPhone (que tiene todo el historial) al reloj; es pequeño a propósito.
public struct RunRecordBoard: Codable, Hashable, Sendable {
    public struct Mark: Codable, Hashable, Sendable {
        public let id: UUID
        public let date: Date
        public let value: Double
    }

    public var top: [RunRecordCategory: [Mark]] = [:]
    public var counts: [RunRecordCategory: Int] = [:]
    public var updatedAt: Date = .distantPast

    public init() {}

    /// Puestos de una carrera nueva frente a la tabla.
    public func placements(for entry: RunRecordEntry) -> [RunRecordPlacement] {
        RunRecordCategory.allCases.compactMap { category in
            guard let value = entry.values[category] else { return nil }
            let all = top[category] ?? []
            let included = all.contains { $0.id == entry.id }
            let marks = all.filter { $0.id != entry.id }
            let previous = max((counts[category] ?? 0) - (included ? 1 : 0), marks.count)
            return RunRecords.placement(category: category, value: value, better: marks.filter { category.isBetter($0.value, than: value) }.count, previousCount: previous, previousBest: marks.first?.value)
        }
    }

    /// Suma la carrera a la tabla (el reloj lo hace al terminar, sin esperar al iPhone).
    public mutating func add(_ entry: RunRecordEntry) {
        for (category, value) in entry.values {
            var marks = (top[category] ?? []).filter { $0.id != entry.id }
            let isNew = marks.count == (top[category] ?? []).count
            marks.append(Mark(id: entry.id, date: entry.date, value: value))
            marks.sort { category.isBetter($0.value, than: $1.value) || ($0.value == $1.value && $0.date < $1.date) }
            top[category] = Array(marks.prefix(RunRecords.podium))
            if isNew { counts[category, default: 0] += 1 }
        }
        updatedAt = Date()
    }
}

/// Récords personales y mejores esfuerzos de carrera.
///
/// - **Mejores esfuerzos** (400 m, 800 m, 1 km, milla, 3 km, 5 km, 10 km,
///   media y maratón): el tramo continuo más rápido de esa distancia en
///   cualquier parte de la carrera, no solo en kilómetros enteros. Ventana
///   deslizante sobre la distancia acumulada con interpolación lineal del
///   instante de inicio: O(n) por distancia.
/// - **Las pausas cuentan**: el tiempo es el del reloj (inicio a fin del tramo,
///   con pausas). Quitar las pausas fabricaría récords de esfuerzo continuo
///   que no existieron.
/// - Solo carreras al aire libre con GPS (en cinta la distancia es estimada).
///   La distancia sale del mismo filtro GPS que en vivo (saltos y precisión
///   pobre descartados; una pérdida de señal no inventa el tramo).
/// - **Calidad**: si la distancia del GPS se aparta más de un 8 % de la que
///   guardó Salud, la carrera no cuenta para los tiempos (ninguna de las dos
///   se da por buena). Un esfuerzo más rápido que 2:30 /km se toma como error.
/// - Sin 100 ni 200 m: con el error del GPS por punto (varios metros), serían
///   segundos de error.
/// - **Distancia** y **duración**: de la carrera entera (también en cinta).
/// - Puesto = 1 + carreras anteriores estrictamente mejores. Se avisa del
///   1.º, 2.º y 3.º solo si hay al menos tantas carreras anteriores como el
///   puesto (ser 2.º de dos no es una marca) y al menos una. Cada carrera
///   aporta un solo esfuerzo por distancia (no se superponen en el ranking).
public enum RunRecords {
    public static let version = "2.0"
    public static let podium = 3
    /// 2:30 /km.
    public static let maximumEffortSpeed = 1000.0 / 150
    public static let maximumDistanceMismatch = 0.08
    /// Carreras más cortas que esto no cuentan para distancia ni duración.
    public static let minimumDistance = 1000.0

    /// Valores de una carrera. `timeline`: puntos con tiempo (con pausas) y
    /// distancia acumulada; vacío en cinta o sin ruta.
    public static func entry(id: UUID, date: Date, distance: Double, duration: TimeInterval, timeline: [EffortPoint], recordedDistance: Double? = nil) -> RunRecordEntry {
        var values: [RunRecordCategory: Double] = [:]
        var starts: [RunRecordCategory: Double] = [:]
        if distance >= minimumDistance, duration > 0 {
            values[.longestDistance] = distance
            values[.longestDuration] = duration
        }
        let gpsDistance = timeline.last?.distance ?? 0
        let consistent = recordedDistance.map { recorded in
            recorded > 0 && abs(gpsDistance - recorded) / recorded <= maximumDistanceMismatch
        } ?? true
        if timeline.count > 1, consistent {
            for category in RunRecordCategory.allCases {
                guard let target = category.effortDistance, let effort = bestEffort(timeline, distance: target) else { continue }
                values[category] = effort.duration
                starts[category] = effort.start
            }
        }
        return RunRecordEntry(id: id, date: date, values: values, starts: starts.isEmpty ? nil : starts)
    }

    /// Tramo continuo más rápido de `distance` metros: (duración, inicio).
    public static func bestEffort(_ timeline: [EffortPoint], distance target: Double) -> (duration: TimeInterval, start: TimeInterval)? {
        guard target > 0, let last = timeline.last, last.distance >= target else { return nil }
        var best: (duration: TimeInterval, start: TimeInterval)?
        var i = 0
        for j in timeline.indices {
            let end = timeline[j]
            guard end.distance >= target else { continue }
            let startDistance = end.distance - target
            // El último punto con distancia ≤ inicio del tramo.
            while i + 1 < j && timeline[i + 1].distance <= startDistance { i += 1 }
            let a = timeline[i], b = timeline[min(i + 1, j)]
            let span = b.distance - a.distance
            let fraction = span > 0 ? min(max((startDistance - a.distance) / span, 0), 1) : 0
            let start = a.time + (b.time - a.time) * fraction
            let duration = end.time - start
            guard duration > 0, target / duration <= maximumEffortSpeed else { continue }
            if best == nil || duration < best!.duration { best = (duration, start) }
        }
        return best
    }

    /// Línea de tiempo (con pausas) con el mismo filtro GPS que en vivo.
    public static func timeline(from route: [LocationSample]) -> [EffortPoint] {
        let sorted = route.sorted { $0.timestamp < $1.timestamp }
        guard let first = sorted.first else { return [] }
        var gps = GPSDistanceAccumulator()
        var points: [EffortPoint] = []
        for sample in sorted where gps.add(sample) {
            let point = EffortPoint(time: sample.timestamp.timeIntervalSince(first.timestamp), distance: gps.distance)
            if point.distance > (points.last?.distance ?? -1) || points.isEmpty { points.append(point) }
        }
        return points
    }

    /// Pulso medio de un tramo [inicio, inicio + duración] (desde el comienzo de la carrera).
    public static func heartRate(_ samples: [HeartRatePoint], runStart: Date, start: TimeInterval, duration: TimeInterval) -> Double? {
        let from = runStart.addingTimeInterval(start), to = from.addingTimeInterval(duration)
        let values = samples.filter { $0.date >= from && $0.date <= to && $0.bpm > 0 }.map(\.bpm)
        return values.count >= 3 ? values.reduce(0, +) / Double(values.count) : nil
    }

    static func placement(category: RunRecordCategory, value: Double, better: Int, previousCount: Int, previousBest: Double?) -> RunRecordPlacement? {
        let rank = better + 1
        guard rank <= podium, previousCount >= 1, previousCount >= rank else { return nil }
        return RunRecordPlacement(category: category, rank: rank, value: value, previousBest: previousBest)
    }

    /// Puestos de una carrera frente a las **anteriores** (como quedó el día que se corrió).
    public static func placements(of entry: RunRecordEntry, among entries: [RunRecordEntry]) -> [RunRecordPlacement] {
        let earlier = entries.filter { $0.id != entry.id && $0.date < entry.date }
        return RunRecordCategory.allCases.compactMap { category in
            guard let value = entry.values[category] else { return nil }
            let previous = earlier.compactMap { $0.values[category] }
            let better = previous.filter { category.isBetter($0, than: value) }.count
            let best = previous.sorted { category.isBetter($0, than: $1) }.first
            return placement(category: category, value: value, better: better, previousCount: previous.count, previousBest: best)
        }
    }

    /// La mejor marca de cada categoría entre dos fechas (récord del año, de 90 días…).
    public static func bests(_ entries: [RunRecordEntry], from start: Date, to end: Date = .distantFuture) -> [RunRecordCategory: RunRecordBoard.Mark] {
        var result: [RunRecordCategory: RunRecordBoard.Mark] = [:]
        for entry in entries where entry.date >= start && entry.date <= end {
            for (category, value) in entry.values {
                if let current = result[category], !category.isBetter(value, than: current.value) { continue }
                result[category] = RunRecordBoard.Mark(id: entry.id, date: entry.date, value: value)
            }
        }
        return result
    }

    /// Cronología de un récord: cada marca que superó a todas las anteriores.
    public static func progression(_ category: RunRecordCategory, entries: [RunRecordEntry]) -> [RunRecordBoard.Mark] {
        var marks: [RunRecordBoard.Mark] = []
        for entry in entries.sorted(by: { $0.date < $1.date }) {
            guard let value = entry.values[category] else { continue }
            if let last = marks.last, !category.isBetter(value, than: last.value) { continue }
            marks.append(RunRecordBoard.Mark(id: entry.id, date: entry.date, value: value))
        }
        return marks
    }

    /// Tabla con las 3 mejores de cada categoría.
    public static func board(_ entries: [RunRecordEntry]) -> RunRecordBoard {
        var board = RunRecordBoard()
        for entry in entries.sorted(by: { $0.date < $1.date }) { board.add(entry) }
        return board
    }
}
