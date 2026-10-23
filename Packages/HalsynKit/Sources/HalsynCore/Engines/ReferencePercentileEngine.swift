import Foundation

/// Sexo biológico tal como lo usan las tablas de referencia publicadas.
public enum ReferenceSex: String, Codable, CaseIterable, Identifiable, Sendable {
    case female
    case male

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .female: "Mujer"
        case .male: "Hombre"
        }
    }
}

/// Fila de una tabla de referencia: un grupo de edad y sexo con sus percentiles.
public struct ReferenceRow: Hashable, Codable, Sendable {
    public let sex: ReferenceSex
    public let ageRange: ClosedRange<Int>
    /// Tamaño de muestra del grupo, si la fuente lo da.
    public let sampleSize: Int?
    /// Percentil (p. ej. 2,5, 10, 50) → valor de la métrica.
    public let percentiles: [Double: Double]

    public init(sex: ReferenceSex, ageRange: ClosedRange<Int>, sampleSize: Int?, percentiles: [Double: Double]) {
        self.sex = sex
        self.ageRange = ageRange
        self.sampleSize = sampleSize
        self.percentiles = percentiles
    }
}

/// Tabla publicada y verificada, con su procedencia.
public struct ReferenceDataset: Hashable, Sendable, Identifiable {
    public let id: String
    public let metric: MetricKind
    /// Cita completa.
    public let citation: String
    public let url: String
    public let population: String
    public let method: String
    /// Diferencias con la medición del Apple Watch y otras limitaciones.
    public let caveats: [String]
    /// `true` si un valor más alto es mejor (VO₂ máx.); `false` si más bajo (FC en reposo).
    public let higherIsBetter: Bool
    public let rows: [ReferenceRow]

    public init(id: String, metric: MetricKind, citation: String, url: String, population: String, method: String, caveats: [String], higherIsBetter: Bool, rows: [ReferenceRow]) {
        self.id = id
        self.metric = metric
        self.citation = citation
        self.url = url
        self.population = population
        self.method = method
        self.caveats = caveats
        self.higherIsBetter = higherIsBetter
        self.rows = rows
    }

    public var ageCoverage: ClosedRange<Int>? {
        guard let low = rows.map(\.ageRange.lowerBound).min(), let high = rows.map(\.ageRange.upperBound).max() else { return nil }
        return low...high
    }
}

/// Posición de un valor dentro de su grupo de referencia.
public struct ReferencePosition: Hashable, Sendable {
    public enum Bound: Hashable, Sendable {
        /// Por debajo del percentil más bajo publicado.
        case below(Double)
        /// Por encima del percentil más alto publicado.
        case above(Double)
        /// Interpolado entre dos percentiles publicados.
        case within(Double)
    }

    public let value: Double
    public let bound: Bound
    public let row: ReferenceRow
    public let dataset: ReferenceDataset

    /// Percentil aproximado para mostrar (redondeado); `nil` fuera de la tabla.
    public var percentile: Int? {
        if case let .within(value) = bound { return Int(value.rounded()) }
        return nil
    }

    /// Mediana del grupo (para comparar), si la tabla la publica.
    public var median: Double? { row.percentiles[50] }
}

/// Coloca un valor del usuario en la tabla de su edad y sexo.
///
/// - Solo usa tablas incluidas en `ReferenceLibrary` (verificadas, con cita).
/// - Interpola linealmente entre percentiles publicados; fuera de ellos dice
///   "por debajo del Pn" o "por encima del Pn", sin extrapolar.
/// - Sin edad, sin sexo o fuera de la cobertura de edad de la tabla: `nil`.
public enum ReferencePercentileEngine {
    public static func position(of value: Double, metric: MetricKind, age: Int, sex: ReferenceSex, library: [ReferenceDataset] = ReferenceLibrary.datasets) -> ReferencePosition? {
        guard let dataset = library.first(where: { $0.metric == metric }),
              let row = dataset.rows.first(where: { $0.sex == sex && $0.ageRange.contains(age) }) else { return nil }
        let points = row.percentiles.sorted { $0.key < $1.key }
        guard let first = points.first, let last = points.last else { return nil }
        // Las tablas son crecientes con el percentil (valor más alto = percentil más alto).
        if value < first.value { return ReferencePosition(value: value, bound: .below(first.key), row: row, dataset: dataset) }
        if value > last.value { return ReferencePosition(value: value, bound: .above(last.key), row: row, dataset: dataset) }
        for (lower, upper) in zip(points, points.dropFirst()) where value >= lower.value && value <= upper.value {
            let span = upper.value - lower.value
            let fraction = span > 0 ? (value - lower.value) / span : 0
            let percentile = lower.key + fraction * (upper.key - lower.key)
            return ReferencePosition(value: value, bound: .within(percentile), row: row, dataset: dataset)
        }
        return ReferencePosition(value: value, bound: .within(last.key), row: row, dataset: dataset)
    }

    /// Edad cumplida en `date`.
    public static func age(birthDate: Date, on date: Date, calendar: Calendar) -> Int? {
        calendar.dateComponents([.year], from: birthDate, to: date).year
    }
}
