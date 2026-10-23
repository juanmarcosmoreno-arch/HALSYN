import Foundation

/// Señal que hoy se aparta de tu rango habitual en la dirección de "cuerpo cargado".
public struct BodySignal: Hashable, Identifiable, Sendable {
    public let metric: MetricKind
    public let value: Double
    public let baselineMean: Double
    /// Desviación en unidades de tu variación habitual (z).
    public let deviation: Double

    public var id: MetricKind { metric }
    public var difference: Double { value - baselineMean }
}

/// Resultado del chequeo de señales de hoy.
public struct UnusualSignals: Hashable, Sendable {
    public let day: Date
    public let signals: [BodySignal]
    /// Métricas que se pudieron comparar (con valor hoy y base suficiente).
    public let checked: [MetricKind]

    /// Dos o más señales a la vez: vale la pena avisar.
    public var isNotable: Bool { signals.count >= 2 }
}

/// Qué tipo de entreno encaja hoy, sin prescribir nada.
public enum TrainingGuidance: String, Hashable, Sendable {
    case push
    case steady
    case easy
    case rest
    case unknown
}

/// Chequeo matutino: recuperación y señales inusuales → sugerencia del día.
///
/// - Señales: FC en reposo, temperatura de muñeca y frecuencia respiratoria
///   por encima de lo habitual, o HRV por debajo, con |z| ≥ 2 frente a los
///   28 días anteriores (mínimo 14 días de base). Cada métrica tiene una
///   variación mínima para no reaccionar a diferencias minúsculas.
/// - Es una observación de bienestar, no un diagnóstico: el texto lo dice.
public struct ReadinessEngine: Sendable {
    public static let signalMetrics: [MetricKind] = [.restingHeartRate, .heartRateVariability, .respiratoryRate, .wristTemperature]

    public var threshold = 2.0
    public var baselineDays = 28
    public var minimumBaselineDays = 14

    public init() {}

    /// Desviación típica mínima por métrica (ruido normal de medida).
    static func minimumSpread(_ metric: MetricKind) -> Double {
        switch metric {
        case .restingHeartRate: 2
        case .heartRateVariability: 5
        case .respiratoryRate: 0.4
        case .wristTemperature: 0.15
        default: 1
        }
    }

    /// `true` si subir es la dirección de "cuerpo cargado".
    static func risesWhenStrained(_ metric: MetricKind) -> Bool {
        metric != .heartRateVariability
    }

    public func signals(history: DailyHistory, on day: Date) -> UnusualSignals {
        let today = history.calendar.startOfDay(for: day)
        var signals: [BodySignal] = []
        var checked: [MetricKind] = []
        for metric in Self.signalMetrics {
            guard let value = history.value(metric, on: today) else { continue }
            let baseline = history.values(metric, daysBefore: today, count: baselineDays)
            guard baseline.count >= minimumBaselineDays, let mean = Stats.mean(baseline),
                  let spread = Stats.standardDeviation(baseline) else { continue }
            checked.append(metric)
            let z = (value - mean) / max(spread, Self.minimumSpread(metric))
            let strained = Self.risesWhenStrained(metric) ? z >= threshold : z <= -threshold
            if strained {
                signals.append(BodySignal(metric: metric, value: value, baselineMean: mean, deviation: z))
            }
        }
        return UnusualSignals(day: today, signals: signals, checked: checked)
    }

    /// Sugerencia a partir de la recuperación de hoy (0–100) y las señales.
    public static func guidance(recovery: Int?, signals: UnusualSignals?) -> TrainingGuidance {
        if signals?.isNotable == true { return .rest }
        guard let recovery else { return .unknown }
        let hasSignal = !(signals?.signals.isEmpty ?? true)
        switch recovery {
        case 67...: return hasSignal ? .steady : .push
        case 34..<67: return hasSignal ? .easy : .steady
        default: return .easy
        }
    }
}

extension HealthDataProviding {
    /// Señales de hoy frente a los 28 días anteriores.
    public func unusualSignals(on day: Date, calendar: Calendar, engine: ReadinessEngine = ReadinessEngine()) async -> UnusualSignals {
        var series: [MetricSeries] = []
        for metric in ReadinessEngine.signalMetrics {
            series.append(await dailySeries(metric, days: engine.baselineDays + 1, endingOn: day))
        }
        return engine.signals(history: DailyHistory(series: series, calendar: calendar), on: day)
    }
}
