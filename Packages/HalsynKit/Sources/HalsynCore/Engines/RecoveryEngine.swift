import Foundation

/// Componentes de la recuperación estimada de VILA.
public enum RecoveryComponentKind: String, CaseIterable, Hashable, Sendable {
    case heartRateVariability
    case restingHeartRate
    case sleep
    case recentLoad

    public var title: String {
        switch self {
        case .heartRateVariability: "HRV frente a tu media"
        case .restingHeartRate: "FC en reposo frente a tu media"
        case .sleep: "Sueño de anoche"
        case .recentLoad: "Esfuerzo de los últimos 3 días"
        }
    }

    public var systemImage: String {
        switch self {
        case .heartRateVariability: "waveform.path.ecg"
        case .restingHeartRate: "heart"
        case .sleep: "moon"
        case .recentLoad: "figure.run"
        }
    }
}

/// Un componente con su puntuación o el motivo por el que falta.
public struct RecoveryComponent: Hashable, Identifiable, Sendable {
    public let kind: RecoveryComponentKind
    public let score: Int?
    public let weight: Double
    public let missingReason: DimensionScore.MissingReason?
    /// Valor que explica el componente:
    /// HRV → diferencia relativa (fracción); FC reposo → diferencia en lpm;
    /// sueño → horas; carga → cociente 3 días / media de 28.
    public let detail: Double?
    public let impact: ScoreImpact
    /// `true` si el valor es del día anterior (aún no hay medición de hoy).
    public let usesPreviousDay: Bool

    public var id: RecoveryComponentKind { kind }
}

/// Recuperación estimada (0–100) de un día, con su desglose.
public struct RecoveryEstimate: Hashable, Identifiable, Sendable {
    public let day: Date
    public let value: Int?
    public let components: [RecoveryComponent]
    public let coverage: Double
    public let confidence: ScoreConfidence
    public let origin: DataOrigin
    public let engineVersion: String

    public var id: Date { day }

    public var band: ScoreBand? { value.map { ScoreBand(score: $0) } }

    public var dailyScore: DailyScore? {
        value.map { DailyScore(day: day, value: $0, weeklyChange: nil, origin: origin) }
    }
}

public struct RecoveryConfiguration: Sendable {
    public var weights: [RecoveryComponentKind: Double]
    public var minimumCoverage: Double
    public var baselineDays: Int
    public var minimumBaselineDays: Int
    public var recommendedSleep: ClosedRange<Double>

    public init(
        weights: [RecoveryComponentKind: Double] = [.heartRateVariability: 0.35, .restingHeartRate: 0.25, .sleep: 0.25, .recentLoad: 0.15],
        minimumCoverage: Double = 0.6,
        baselineDays: Int = 28,
        minimumBaselineDays: Int = 7,
        recommendedSleep: ClosedRange<Double> = 7...9
    ) {
        self.weights = weights
        self.minimumCoverage = minimumCoverage
        self.baselineDays = baselineDays
        self.minimumBaselineDays = minimumBaselineDays
        self.recommendedSleep = recommendedSleep
    }

    public func weight(_ kind: RecoveryComponentKind) -> Double { max(0, weights[kind] ?? 0) }
}

/// Motor de recuperación estimada de VILA.
///
/// Reglas (Documentation/RECOVERY.md):
/// - **HRV** y **FC en reposo** del día frente a tu media de los 28 días
///   anteriores (mínimo 7). En tu media = 75; mejor que tu media sube hasta 100
///   (+2 desviaciones); peor baja hasta 15 (−3 desviaciones). Si aún no hay
///   valor de hoy se usa el de ayer y se indica.
/// - **Sueño** de la noche que termina ese día frente a 7–9 h (misma curva que HÄLSA).
/// - **Esfuerzo reciente**: minutos de ejercicio de los 3 días anteriores frente
///   a tu media de 28 días. Igual o por debajo de lo habitual = 100; el doble y
///   medio o más = 40.
/// - Hace falta al menos HRV o FC en reposo (una señal fisiológica) y el 60 % del peso.
/// - Es una estimación orientativa, no un diagnóstico: no dice si estás
///   médicamente recuperado.
public struct RecoveryEngine: Sendable {
    public static let version = "0.1-provisional"
    public static let inputs: [MetricKind] = [.heartRateVariability, .restingHeartRate, .sleepDuration, .exerciseTime]

    public let configuration: RecoveryConfiguration

    public init(configuration: RecoveryConfiguration = RecoveryConfiguration()) {
        self.configuration = configuration
    }

    public var historyDaysNeeded: Int { configuration.baselineDays + 2 }

    public func evaluate(day: Date, history: DailyHistory, origin: DataOrigin) -> RecoveryEstimate {
        let start = history.calendar.startOfDay(for: day)
        let components = RecoveryComponentKind.allCases.map { component($0, day: start, history: history) }
        let totalWeight = components.reduce(0) { $0 + $1.weight }
        let available = components.filter { $0.score != nil && $0.weight > 0 }
        let availableWeight = available.reduce(0) { $0 + $1.weight }
        let coverage = totalWeight > 0 ? availableWeight / totalWeight : 0
        let hasPhysiology = available.contains { $0.kind == .heartRateVariability || $0.kind == .restingHeartRate }

        var value: Int?
        if hasPhysiology, coverage >= configuration.minimumCoverage, availableWeight > 0 {
            value = Int((available.reduce(0.0) { $0 + Double($1.score ?? 0) * $1.weight } / availableWeight).rounded())
        }

        let depth = [MetricKind.heartRateVariability, .restingHeartRate]
            .map { history.values($0, daysBefore: start, count: configuration.baselineDays).count }
            .max() ?? 0
        let usesYesterday = available.contains(where: \.usesPreviousDay)
        let confidence: ScoreConfidence
        if coverage >= 0.9 && depth >= 14 && !usesYesterday {
            confidence = .high
        } else if coverage >= 0.75 {
            confidence = .medium
        } else {
            confidence = .low
        }
        return RecoveryEstimate(day: start, value: value, components: components, coverage: coverage, confidence: confidence, origin: origin, engineVersion: Self.version)
    }

    private func component(_ kind: RecoveryComponentKind, day: Date, history: DailyHistory) -> RecoveryComponent {
        let weight = configuration.weight(kind)
        func missing(_ reason: DimensionScore.MissingReason) -> RecoveryComponent {
            RecoveryComponent(kind: kind, score: nil, weight: weight, missingReason: reason, detail: nil, impact: .neutral, usesPreviousDay: false)
        }
        switch kind {
        case .heartRateVariability, .restingHeartRate:
            let metric: MetricKind = kind == .heartRateVariability ? .heartRateVariability : .restingHeartRate
            var reference = day
            var usesPrevious = false
            var value = history.value(metric, on: day)
            if value == nil, let yesterday = history.calendar.date(byAdding: .day, value: -1, to: day) {
                value = history.value(metric, on: yesterday)
                reference = yesterday
                usesPrevious = value != nil
            }
            guard let value else { return missing(.noData) }
            let baseline = history.values(metric, daysBefore: reference, count: configuration.baselineDays)
            guard baseline.count >= configuration.minimumBaselineDays else { return missing(.insufficientHistory) }
            let stats = Statistics(baseline)
            let z: Double
            let detail: Double
            if metric == .heartRateVariability {
                z = (value - stats.mean) / max(stats.standardDeviation, stats.mean * 0.05, 1)
                detail = stats.mean > 0 ? (value - stats.mean) / stats.mean : 0
            } else {
                // FC en reposo más baja de lo habitual es favorable: se invierte el signo.
                z = -(value - stats.mean) / max(stats.standardDeviation, 2)
                detail = value - stats.mean
            }
            let impact: ScoreImpact = z <= -1 ? .negative : (z >= 0.5 ? .positive : .neutral)
            return RecoveryComponent(kind: kind, score: Int(Self.baselineScore(z: z).rounded()), weight: weight, missingReason: nil, detail: detail, impact: impact, usesPreviousDay: usesPrevious)
        case .sleep:
            guard let hours = history.value(.sleepDuration, on: day) else { return missing(.noData) }
            let range = configuration.recommendedSleep
            let impact: ScoreImpact = range.contains(hours) ? .positive : (hours < range.lowerBound - 1 ? .negative : .neutral)
            return RecoveryComponent(kind: kind, score: Int(HealthScoreEngine.sleepScore(hours: hours, recommended: range).rounded()), weight: weight, missingReason: nil, detail: hours, impact: impact, usesPreviousDay: false)
        case .recentLoad:
            let chronicValues = history.values(.exerciseTime, daysBefore: day, count: configuration.baselineDays)
            guard !chronicValues.isEmpty else { return missing(.noData) }
            guard chronicValues.count >= 14 else { return missing(.insufficientHistory) }
            let chronic = chronicValues.reduce(0, +) / Double(configuration.baselineDays)
            guard chronic >= 5 else { return missing(.insufficientHistory) }
            // Los días sin registro cuentan como 0 min (suma de esfuerzo).
            let acute = history.values(.exerciseTime, daysBefore: day, count: 3).reduce(0, +) / 3
            let ratio = acute / chronic
            let impact: ScoreImpact = ratio > 1.5 ? .negative : (ratio <= 1 ? .positive : .neutral)
            return RecoveryComponent(kind: kind, score: Int(Self.recentLoadScore(ratio: ratio).rounded()), weight: weight, missingReason: nil, detail: ratio, impact: impact, usesPreviousDay: false)
        }
    }

    // MARK: Curvas (públicas para tests y documentación)

    /// `z` = desviación favorable en desviaciones típicas (positivo = mejor que tu media).
    /// 75 en tu media; +2 → 100; −3 → 15 (lineal por tramos).
    public static func baselineScore(z: Double) -> Double {
        let clamped = min(max(z, -3), 2)
        return clamped >= 0 ? 75 + 12.5 * clamped : 75 + 20 * clamped
    }

    /// 100 hasta 1 (lo habitual o menos); baja lineal hasta 40 en 2,5.
    public static func recentLoadScore(ratio: Double) -> Double {
        if ratio <= 1 { return 100 }
        if ratio >= 2.5 { return 40 }
        return 100 - (ratio - 1) / 1.5 * 60
    }
}

extension HealthDataProviding {
    /// Recuperación de los `days` días que terminan en `end`, con el mismo motor
    /// para demo y Apple Health. Incluye los días sin estimación (`value == nil`).
    public func computeRecovery(
        endingOn end: Date,
        days: Int,
        engine: RecoveryEngine = RecoveryEngine(),
        calendar: Calendar,
        origin: DataOrigin
    ) async -> [RecoveryEstimate] {
        guard days > 0 else { return [] }
        let lastDay = calendar.startOfDay(for: end)
        let fetchDays = days + engine.historyDaysNeeded
        var series: [MetricSeries] = []
        for kind in RecoveryEngine.inputs {
            series.append(await dailySeries(kind, days: fetchDays, endingOn: lastDay))
        }
        let history = DailyHistory(series: series, calendar: calendar)
        return (0..<days).reversed().compactMap { offset in
            calendar.date(byAdding: .day, value: -offset, to: lastDay).map { engine.evaluate(day: $0, history: history, origin: origin) }
        }
    }
}
