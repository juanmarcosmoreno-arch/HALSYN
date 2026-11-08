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
    /// Porcentaje de la FC umbral (la media de los últimos 20 min de una prueba
    /// a tope de 30 min, método de Friel): Z1 < 85 %, Z2 85–89 %, Z3 90–94 %,
    /// Z4 95–99 %, Z5 ≥ 100 %.
    case lactateThreshold

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .percentOfMax: "Porcentaje de la FC máxima"
        case .heartRateReserve: "Reserva cardíaca (Karvonen)"
        case .lactateThreshold: "FC umbral (lactato)"
        }
    }
}

/// De dónde sale la FC máxima. Nunca se estima por edad sin decirlo.
public enum MaxHeartRateSource: String, Codable, CaseIterable, Identifiable, Sendable {
    /// Introducida por el usuario (p. ej. de una prueba de esfuerzo).
    case manual
    /// La más alta registrada en sus carreras recientes en Apple Health.
    case observed
    /// Validada por HÅLSYN: la más alta repetida en al menos dos sesiones
    /// (`MaxHeartRateValidator`). Un pico aislado no basta.
    case validated

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .manual: "Introducida por ti"
        case .observed: "Máxima registrada en tus carreras"
        case .validated: "Validada por HÅLSYN (repetida en varias sesiones)"
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
    /// FC umbral (lactato) para el método de Friel. Opcional.
    public var thresholdHeartRate: Double?
    /// La FC máxima que introdujiste tú. Se conserva aunque elijas otra
    /// fuente (`maxHeartRate` guarda la que está en uso). `nil` en ajustes
    /// anteriores a 0.10.0 (107): entonces es `maxHeartRate` si la fuente es manual.
    public var configuredMaxHeartRate: Double?

    /// La FC máxima introducida por ti, si la hay.
    public var configuredMax: Double? {
        configuredMaxHeartRate ?? (maxSource == .manual ? maxHeartRate : nil)
    }

    public static let plausibleThresholdRange: ClosedRange<Double> = 110...210
    /// Inicio de cada zona como fracción de la FC umbral (Z1 desde el 65 %).
    public static let thresholdBoundaries: [Double] = [0.65, 0.85, 0.90, 0.95, 1.0]

    public init(method: HeartRateZoneMethod = .percentOfMax, maxSource: MaxHeartRateSource = .manual, maxHeartRate: Double? = nil, restingHeartRate: Double? = nil, thresholdHeartRate: Double? = nil) {
        self.method = method
        self.maxSource = maxSource
        self.maxHeartRate = maxHeartRate
        self.restingHeartRate = restingHeartRate
        self.thresholdHeartRate = thresholdHeartRate
    }

    /// Método que se aplica de verdad: Karvonen necesita una FC en reposo
    /// válida y el umbral una FC umbral válida; si no, % de la máxima.
    public var effectiveMethod: HeartRateZoneMethod {
        switch method {
        case .lactateThreshold:
            return validThreshold != nil ? .lactateThreshold : .percentOfMax
        case .heartRateReserve:
            guard let resting = validResting, let max = validMax, resting < max else { return .percentOfMax }
            return .heartRateReserve
        case .percentOfMax:
            return .percentOfMax
        }
    }

    /// Las zonas son aproximadas: salen de la FC máxima registrada (la real
    /// puede ser más alta) y no de una FC umbral medida.
    public var isApproximate: Bool {
        effectiveMethod != .lactateThreshold && maxSource != .manual
    }

    public var validThreshold: Double? {
        thresholdHeartRate.flatMap { Self.plausibleThresholdRange.contains($0) ? $0 : nil }
    }

    private var validMax: Double? {
        maxHeartRate.flatMap { Self.plausibleMaxRange.contains($0) ? $0 : nil }
    }

    private var validResting: Double? {
        restingHeartRate.flatMap { Self.plausibleRestingRange.contains($0) ? $0 : nil }
    }

    /// Las 5 zonas, o vacío si no hay FC máxima plausible.
    public var zones: [HeartRateZone] {
        if effectiveMethod == .lactateThreshold, let threshold = validThreshold {
            let top = Swift.max(validMax ?? threshold * 1.1, threshold * 1.02)
            let starts = Self.thresholdBoundaries.map { (threshold * $0).rounded() }
            return (0..<5).map { index in
                HeartRateZone(index: index + 1, lowerBound: starts[index], upperBound: index < 4 ? starts[index + 1] : top.rounded())
            }
        }
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
    /// Sin duplicados ni entrenamientos con pulso inválido.
    public static func observedMax(in workouts: [WorkoutSummary]) -> Double? {
        let quality = DataQuality.assess(workouts)
        return workouts.filter { quality[$0.id]?.level != .excluded && quality[$0.id]?.heartRateUsable != false }
            .compactMap(\.maxHeartRate).filter { plausibleMaxRange.contains($0) }.max()
    }

    /// FC máxima que usan la intensidad y el modelo, según la fuente que
    /// elegiste (desde 0.10.0 (107) no se cambia en silencio):
    /// - **Introducida por ti**: la tuya, aunque quede por debajo de la
    ///   validada (entonces se avisa). Si no hay una válida, la validada.
    /// - **Registrada**: la más alta presente en Salud.
    /// - **Validada**: la más alta repetida en dos sesiones o más.
    public static func resolveMax(_ configuration: HeartRateZoneConfiguration, runs: [WorkoutSummary], samples: [UUID: [HeartRatePoint]] = [:], today: Date, calendar: Calendar) -> MaxHeartRateResolution {
        let assessment = MaxHeartRateValidator.assess(runs: runs, samples: samples, today: today, calendar: calendar)
        let configured = configuration.configuredMax.flatMap { plausibleMaxRange.contains($0) ? $0 : nil }
        let value: Double?
        var fallback = false
        switch configuration.maxSource {
        case .manual:
            value = configured ?? assessment.validated
            fallback = configured == nil && assessment.validated != nil
        case .observed:
            value = assessment.recorded
        case .validated:
            value = assessment.validated
        }
        return MaxHeartRateResolution(source: configuration.maxSource, value: value, configured: configured, assessment: assessment, usesValidatedFallback: fallback)
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

/// La FC máxima en uso y las tres que se conservan por separado.
public struct MaxHeartRateResolution: Hashable, Sendable {
    public let source: MaxHeartRateSource
    /// La que usan zonas, intensidad y modelo.
    public let value: Double?
    /// La que introdujiste (se conserva aunque elijas otra fuente).
    public let configured: Double?
    public let assessment: MaxHeartRateAssessment
    /// Fuente manual sin un valor válido: se usa la validada.
    public let usesValidatedFallback: Bool

    public var recorded: Double? { assessment.recorded }
    public var validated: Double? { assessment.validated }
    /// La configurada queda más de 2 lpm por debajo de la validada: no se
    /// cambia, pero se avisa (los rodajes parecerán más intensos).
    public var configuredBelowValidated: Bool {
        guard source == .manual, let configured, let validated else { return false }
        return configured < validated - 2
    }
}
