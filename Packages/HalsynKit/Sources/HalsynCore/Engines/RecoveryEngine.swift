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
/// Reglas (Documentation/RECOVERY.md, versión 0.2):
/// - **Línea basal robusta**: mediana y MAD × 1,4826 (equivalente a una
///   desviación típica sin que un valor raro la mueva) de los 28 días
///   anteriores (mínimo 7).
/// - **HRV**: media de los últimos 3 días con dato (mínimo 2, si no el del día),
///   para no interpretar una sola medición; frente a la línea basal de los 28
///   días previos a esa ventana.
/// - **FC en reposo**: la del día (o la de ayer, y se indica) frente a su línea basal.
/// - En la línea basal = 75; mejor sube hasta 100 (+2); peor baja hasta 15 (−3).
/// - **Sueño** de la noche que termina ese día: el menor entre la curva de
///   7–9 h (la de HÄLSA) y la comparación con **tu sueño habitual** (mediana
///   de 28 noches): sin penalización hasta 30 min por debajo, y 25 puntos
///   menos por cada hora más.
/// - **Esfuerzo reciente**: minutos de ejercicio de los 3 días anteriores frente
///   a tu media de 28 días. Igual o por debajo de lo habitual = 100; el doble y
///   medio o más = 40.
/// - Hace falta al menos HRV o FC en reposo (una señal fisiológica) y el 60 % del peso.
/// - Es una estimación orientativa, no un diagnóstico: no dice si estás
///   médicamente recuperado.
public struct RecoveryEngine: Sendable {
    public static let version = "0.2"
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
            guard var value else { return missing(.noData) }
            var baselineEnd = reference
            if metric == .heartRateVariability {
                // Media móvil de 3 días: una sola medición de HRV es muy ruidosa.
                let window = [0, 1, 2].compactMap { offset -> Double? in
                    history.calendar.date(byAdding: .day, value: -offset, to: reference).flatMap { history.value(metric, on: $0) }
                }
                if window.count >= 2 { value = window.reduce(0, +) / Double(window.count) }
                baselineEnd = history.calendar.date(byAdding: .day, value: -2, to: reference) ?? reference
            }
            let baseline = history.values(metric, daysBefore: baselineEnd, count: configuration.baselineDays)
            guard baseline.count >= configuration.minimumBaselineDays else { return missing(.insufficientHistory) }
            let robust = RobustBaseline(baseline)
            let z: Double
            let detail: Double
            if metric == .heartRateVariability {
                z = (value - robust.median) / max(robust.scale, robust.median * 0.05, 1)
                detail = robust.median > 0 ? (value - robust.median) / robust.median : 0
            } else {
                // FC en reposo más baja de lo habitual es favorable: se invierte el signo.
                z = -(value - robust.median) / max(robust.scale, 2)
                detail = value - robust.median
            }
            let impact: ScoreImpact = z <= -1 ? .negative : (z >= 0.5 ? .positive : .neutral)
            return RecoveryComponent(kind: kind, score: Int(Self.baselineScore(z: z).rounded()), weight: weight, missingReason: nil, detail: detail, impact: impact, usesPreviousDay: usesPrevious)
        case .sleep:
            guard let hours = history.value(.sleepDuration, on: day) else { return missing(.noData) }
            let range = configuration.recommendedSleep
            var score = HealthScoreEngine.sleepScore(hours: hours, recommended: range)
            let habitual = history.values(.sleepDuration, daysBefore: day, count: configuration.baselineDays)
            var belowHabit = false
            if habitual.count >= configuration.minimumBaselineDays {
                let personal = Self.personalSleepScore(hours: hours, habitual: RobustBaseline(habitual).median)
                belowHabit = personal < 100
                score = min(score, personal)
            }
            let impact: ScoreImpact = range.contains(hours) && !belowHabit ? .positive : (hours < range.lowerBound - 1 || score < 60 ? .negative : .neutral)
            return RecoveryComponent(kind: kind, score: Int(score.rounded()), weight: weight, missingReason: nil, detail: hours, impact: impact, usesPreviousDay: false)
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

    /// Sueño frente a tu sueño habitual: 100 hasta 30 min por debajo; luego
    /// 25 puntos menos por hora, sin bajar de 30.
    public static func personalSleepScore(hours: Double, habitual: Double) -> Double {
        let shortfall = habitual - 0.5 - hours
        guard shortfall > 0 else { return 100 }
        return max(30, 100 - 25 * shortfall)
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

/// Línea basal robusta: mediana y MAD escalada (× 1,4826, equivalente a la
/// desviación típica en una normal). Un valor aislado no la mueve.
public struct RobustBaseline: Hashable, Sendable {
    public let median: Double
    public let scale: Double

    public init(_ values: [Double]) {
        let sorted = values.sorted()
        func medianOf(_ items: [Double]) -> Double {
            guard !items.isEmpty else { return 0 }
            let middle = items.count / 2
            return items.count.isMultiple(of: 2) ? (items[middle - 1] + items[middle]) / 2 : items[middle]
        }
        let center = medianOf(sorted)
        median = center
        scale = 1.4826 * medianOf(sorted.map { abs($0 - center) }.sorted())
    }
}
