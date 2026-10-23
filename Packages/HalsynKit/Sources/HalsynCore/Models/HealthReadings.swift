import Foundation

/// Origen de un dato. Toda pantalla debe poder decir de dónde viene lo que muestra.
public enum DataOrigin: Hashable, Codable, Sendable {
    /// Dato sintético del modo demo. Nunca debe presentarse como medición real.
    case demo
    /// Dato leído de Apple Health, con el nombre de la fuente si se conoce.
    case healthKit(sourceName: String?)
    /// Valor calculado por un motor de HÅLSYN a partir de otros datos.
    case derived(engine: String)

    public var isDemo: Bool {
        if case .demo = self { return true }
        return false
    }

    public var label: String {
        switch self {
        case .demo: "Datos demo"
        case .healthKit(let source): source.map { "Apple Health · \($0)" } ?? "Apple Health"
        case .derived(let engine): "Calculado por \(engine)"
        }
    }
}

/// Una lectura puntual o agregada de una métrica.
public struct MetricReading: Hashable, Identifiable, Sendable {
    public let kind: MetricKind
    public let value: Double
    public let date: Date
    public let origin: DataOrigin

    public var id: String { "\(kind.rawValue)-\(date.timeIntervalSinceReferenceDate)" }

    public init(kind: MetricKind, value: Double, date: Date, origin: DataOrigin) {
        self.kind = kind
        self.value = value
        self.date = date
        self.origin = origin
    }
}

/// Resultado de pedir una métrica. Distingue explícitamente entre ausencia de
/// datos, permiso denegado y métricas no soportadas, para no confundir nunca
/// "no hay dato" con "valor normal".
public enum MetricAvailability: Hashable, Sendable {
    case available(MetricReading)
    /// Hay permiso (o no se puede saber) pero no hay muestras en el periodo.
    case noData
    /// El usuario no ha concedido acceso de lectura.
    case notAuthorized
    /// El dispositivo o el SDK no ofrecen esta métrica.
    case unsupported
    /// Los datos existen pero están protegidos mientras el dispositivo está bloqueado.
    case temporarilyUnavailable
    /// La lectura falló (error del almacén); se puede reintentar.
    case readFailed

    public var reading: MetricReading? {
        if case .available(let reading) = self { return reading }
        return nil
    }

    public var statusMessage: String {
        switch self {
        case .available: ""
        case .noData: "Sin datos en este periodo"
        case .notAuthorized: "Acceso no concedido"
        case .unsupported: "No disponible en este dispositivo"
        case .temporarilyUnavailable: "Protegido mientras el dispositivo está bloqueado"
        case .readFailed: "No se pudieron leer los datos"
        }
    }
}

/// Valor diario agregado para series temporales.
public struct DailyValue: Hashable, Identifiable, Sendable {
    public let day: Date
    public let value: Double

    public var id: Date { day }

    public init(day: Date, value: Double) {
        self.day = day
        self.value = value
    }
}

public struct MetricSeries: Hashable, Sendable {
    public let kind: MetricKind
    public let values: [DailyValue]
    public let origin: DataOrigin

    public init(kind: MetricKind, values: [DailyValue], origin: DataOrigin) {
        self.kind = kind
        self.values = values
        self.origin = origin
    }

    public var average: Double? {
        guard !values.isEmpty else { return nil }
        return values.map(\.value).reduce(0, +) / Double(values.count)
    }
}

/// Puntuación diaria (0–100) de bienestar. No es una valoración clínica.
public struct DailyScore: Hashable, Identifiable, Sendable {
    public let day: Date
    public let value: Int
    /// Variación respecto a la media de los 7 días anteriores, en puntos.
    public let weeklyChange: Int?
    public let origin: DataOrigin
    /// Desglose del motor (dimensiones, cobertura, factores). `nil` si no procede.
    public let breakdown: HealthScoreBreakdown?

    public var id: Date { day }

    public init(day: Date, value: Int, weeklyChange: Int?, origin: DataOrigin, breakdown: HealthScoreBreakdown? = nil) {
        self.day = day
        self.value = min(max(value, 0), 100)
        self.weeklyChange = weeklyChange
        self.origin = origin
        self.breakdown = breakdown
    }

    /// Descripción cualitativa no clínica.
    public var band: ScoreBand { ScoreBand(score: value) }
}

public enum ScoreBand: String, Sendable {
    case low, fair, good, excellent

    public init(score: Int) {
        switch score {
        case ..<40: self = .low
        case 40..<65: self = .fair
        case 65..<85: self = .good
        default: self = .excellent
        }
    }

    public var title: String {
        switch self {
        case .low: "Día para cuidarte"
        case .fair: "Condición moderada"
        case .good: "Buena condición"
        case .excellent: "Condición excelente"
        }
    }
}
