import Foundation

/// Método para repartir las zonas cardíacas.
///
/// - `percentOfMax`: porcentaje de la FC máxima.
/// - `heartRateReserve`: método de Karvonen, porcentaje de la reserva
///   (FC máx − FC en reposo) sumado a la FC en reposo.
///
/// Los límites (50/60/70/80/90 %) son el modelo de 5 zonas de uso habitual en
/// entrenamiento; son una convención, no un diagnóstico ni una prescripción
/// (`SCIENTIFIC_REFERENCES.md`).
public enum HeartRateZoneMethod: String, Codable, CaseIterable, Identifiable, Sendable {
    case percentOfMax
    case heartRateReserve

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .percentOfMax: "Porcentaje de la FC máxima"
        case .heartRateReserve: "Reserva cardíaca (Karvonen)"
        }
    }
}

/// De dónde sale la FC máxima. Nunca se estima por edad sin decirlo.
public enum MaxHeartRateSource: String, Codable, CaseIterable, Identifiable, Sendable {
    /// Introducida por el usuario (p. ej. de una prueba de esfuerzo).
    case manual
    /// La más alta registrada en sus carreras recientes en Apple Health.
    case observed

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .manual: "Introducida por ti"
        case .observed: "Máxima registrada en tus carreras"
        }
    }
}

/// Una zona: índice 1...5 y límites en lpm (inferior incluido, superior excluido).
public struct HeartRateZone: Hashable, Identifiable, Sendable {
    public let index: Int
    public let lowerBound: Double
    public let upperBound: Double

    public var id: Int { index }

    public var name: String {
        switch index {
        case 1: "Muy suave"
        case 2: "Suave"
        case 3: "Moderada"
        case 4: "Intensa"
        default: "Máxima"
        }
    }
}

/// Configuración de zonas cardíacas del usuario.
public struct HeartRateZoneConfiguration: Hashable, Codable, Sendable {
    /// Fracciones de inicio de cada zona (Z1…Z5). Z5 llega hasta la FC máxima.
    public static let boundaries: [Double] = [0.5, 0.6, 0.7, 0.8, 0.9]
    public static let plausibleMaxRange: ClosedRange<Double> = 120...230
    public static let plausibleRestingRange: ClosedRange<Double> = 30...100

    public var method: HeartRateZoneMethod
    public var maxSource: MaxHeartRateSource
    /// FC máxima en lpm. `nil` mientras no haya un valor (manual u observado):
    /// sin FC máxima no se calculan zonas.
    public var maxHeartRate: Double?
    /// FC en reposo para Karvonen. Si falta, se usa % de la máxima.
    public var restingHeartRate: Double?

    public init(method: HeartRateZoneMethod = .percentOfMax, maxSource: MaxHeartRateSource = .manual, maxHeartRate: Double? = nil, restingHeartRate: Double? = nil) {
        self.method = method
        self.maxSource = maxSource
        self.maxHeartRate = maxHeartRate
        self.restingHeartRate = restingHeartRate
    }

    /// Método que se aplica de verdad: Karvonen necesita una FC en reposo válida.
    public var effectiveMethod: HeartRateZoneMethod {
        guard method == .heartRateReserve, let resting = validResting, let max = validMax, resting < max else { return .percentOfMax }
        return .heartRateReserve
    }

    private var validMax: Double? {
        maxHeartRate.flatMap { Self.plausibleMaxRange.contains($0) ? $0 : nil }
    }

    private var validResting: Double? {
        restingHeartRate.flatMap { Self.plausibleRestingRange.contains($0) ? $0 : nil }
    }

    /// Las 5 zonas, o vacío si no hay FC máxima plausible.
    public var zones: [HeartRateZone] {
        guard let max = validMax else { return [] }
        let bpm: (Double) -> Double
        if effectiveMethod == .heartRateReserve, let resting = validResting {
            bpm = { resting + (max - resting) * $0 }
        } else {
            bpm = { max * $0 }
        }
        let fractions = Self.boundaries + [1.0]
        return (0..<5).map { index in
            HeartRateZone(index: index + 1, lowerBound: bpm(fractions[index]).rounded(), upperBound: bpm(fractions[index + 1]).rounded())
        }
    }

    /// Zona de una FC. Por debajo de Z1 devuelve 0 ("sin zona"); por encima de
    /// la FC máxima, 5. `nil` si no hay zonas configuradas.
    public func zone(for heartRate: Double) -> Int? {
        let zones = zones
        guard let first = zones.first else { return nil }
        if heartRate < first.lowerBound { return 0 }
        return zones.last { heartRate >= $0.lowerBound }?.index
    }

    /// FC máxima observada: la más alta entre las carreras. Ignora valores no
    /// plausibles (picos de sensor).
    public static func observedMax(in workouts: [WorkoutSummary]) -> Double? {
        workouts.compactMap(\.maxHeartRate).filter { plausibleMaxRange.contains($0) }.max()
    }
}

/// Tiempo pasado en cada zona. Cada lectura de FC cuenta hasta la siguiente,
/// con un máximo de `maximumGap` (si el sensor se calla, no se extrapola).
public struct ZoneTimeAccumulator: Sendable {
    public static let maximumGap: TimeInterval = 15

    /// Segundos por zona; índice 0 = por debajo de Z1.
    public private(set) var seconds: [TimeInterval] = Array(repeating: 0, count: 6)
    private var last: (zone: Int, date: Date)?

    public init() {}

    public mutating func add(zone: Int?, at date: Date) {
        if let last {
            let span = min(max(0, date.timeIntervalSince(last.date)), Self.maximumGap)
            seconds[last.zone] += span
        }
        if let zone, (0...5).contains(zone) {
            last = (zone, date)
        } else {
            last = nil
        }
    }

    /// Cierra el tramo actual en `date` (pausa): el tiempo en pausa no cuenta.
    public mutating func breakSegment(at date: Date) {
        add(zone: nil, at: date)
    }

    public var total: TimeInterval { seconds.reduce(0, +) }
}
