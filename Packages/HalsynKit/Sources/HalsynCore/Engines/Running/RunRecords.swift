import Foundation

/// Categoría de récord personal de carrera.
public enum RunRecordCategory: String, Codable, CaseIterable, Hashable, Identifiable, Sendable {
    case fastestKilometer
    case fastest5K
    case fastest10K
    case longestDistance
    case longestDuration

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .fastestKilometer: "Kilómetro más rápido"
        case .fastest5K: "5 km más rápidos"
        case .fastest10K: "10 km más rápidos"
        case .longestDistance: "Distancia más larga"
        case .longestDuration: "Carrera más larga en tiempo"
        }
    }

    /// Kilómetros seguidos que forman el esfuerzo (solo las de tiempo).
    public var kilometers: Int? {
        switch self {
        case .fastestKilometer: 1
        case .fastest5K: 5
        case .fastest10K: 10
        case .longestDistance, .longestDuration: nil
        }
    }

    /// Mayor es mejor (distancia y duración); en los tiempos, menor.
    public var higherIsBetter: Bool { kilometers == nil }

    func isBetter(_ a: Double, than b: Double) -> Bool {
        higherIsBetter ? a > b : a < b
    }
}

/// Valores de una carrera para cada categoría (segundos o metros).
public struct RunRecordEntry: Codable, Hashable, Identifiable, Sendable {
    public let id: UUID
    public let date: Date
    public var values: [RunRecordCategory: Double]

    public init(id: UUID, date: Date, values: [RunRecordCategory: Double]) {
        self.id = id
        self.date = date
        self.values = values
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

/// Récords personales de carrera.
///
/// - **Tiempos** (1, 5 y 10 km): la mejor suma de kilómetros **completos y
///   seguidos** de los parciales, con el mismo método en el reloj y en el
///   iPhone (vueltas automáticas de 1 km interpoladas, `LapTracker`). Es algo
///   más prudente que buscar el mejor tramo en cualquier punto, y nunca
///   inventa un tiempo más rápido que el que corriste.
/// - Solo carreras al aire libre con GPS (en cinta la distancia es estimada).
///   Se descarta un kilómetro por debajo de 2:30 (salto del GPS).
/// - **Distancia** y **duración**: de toda la carrera (también en cinta).
/// - Puesto = 1 + carreras anteriores estrictamente mejores. Se avisa del
///   1.º, 2.º y 3.º solo si hay al menos tantas carreras anteriores como el
///   puesto (ser 2.º de dos no es una marca) y al menos una.
public enum RunRecords {
    public static let version = "1.0"
    public static let podium = 3
    public static let minimumKilometerSeconds: TimeInterval = 150
    public static let maximumKilometerSeconds: TimeInterval = 1200
    /// Carreras más cortas que esto no cuentan para distancia ni duración.
    public static let minimumDistance = 1000.0

    /// Valores de una carrera. `kilometerSplits`: duración de cada kilómetro completo, en orden.
    public static func entry(id: UUID, date: Date, distance: Double, duration: TimeInterval, kilometerSplits: [TimeInterval], usesGPS: Bool) -> RunRecordEntry {
        var values: [RunRecordCategory: Double] = [:]
        if distance >= minimumDistance, duration > 0 {
            values[.longestDistance] = distance
            values[.longestDuration] = duration
        }
        if usesGPS {
            let plausible = !kilometerSplits.contains { $0 < minimumKilometerSeconds || $0 > maximumKilometerSeconds }
            if plausible {
                for category in RunRecordCategory.allCases {
                    guard let kilometers = category.kilometers, let best = bestSum(kilometerSplits, count: kilometers) else { continue }
                    values[category] = best
                }
            }
        }
        return RunRecordEntry(id: id, date: date, values: values)
    }

    /// Duraciones de los kilómetros completos de unos parciales.
    public static func kilometerDurations(_ splits: [Split]) -> [TimeInterval] {
        splits.filter { $0.isComplete && abs($0.distance - 1000) < 1 }.map(\.duration)
    }

    public static func kilometerDurations(_ laps: [Lap]) -> [TimeInterval] {
        laps.filter { abs($0.distance - 1000) < 1 }.map(\.duration)
    }

    static func bestSum(_ values: [TimeInterval], count: Int) -> TimeInterval? {
        guard count > 0, values.count >= count else { return nil }
        var sum = values.prefix(count).reduce(0, +)
        var best = sum
        for index in count..<values.count {
            sum += values[index] - values[index - count]
            best = min(best, sum)
        }
        return best
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

    /// Tabla con las 3 mejores de cada categoría.
    public static func board(_ entries: [RunRecordEntry]) -> RunRecordBoard {
        var board = RunRecordBoard()
        for entry in entries.sorted(by: { $0.date < $1.date }) { board.add(entry) }
        return board
    }
}
