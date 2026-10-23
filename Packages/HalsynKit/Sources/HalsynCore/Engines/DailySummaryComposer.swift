import Foundation

/// Frase del resumen del día. Solo se genera con datos disponibles; la
/// interfaz compone el texto localizado. No contiene conclusiones médicas.
public enum SummaryStatement: Hashable, Sendable {
    public enum Relation: String, Hashable, Sendable {
        case above, within, below
    }

    /// Pasos de hoy frente a la media personal (días completos anteriores).
    case activity(Relation)
    /// FC en reposo de hoy frente al rango habitual.
    case restingHeartRate(Relation)
    /// Horas dormidas anoche y si están dentro de la recomendación.
    case sleep(hours: Double, withinRecommendation: Bool)
    /// Minutos de ejercicio de los últimos 7 días (incluido hoy) y si alcanzan la referencia.
    case weeklyExercise(minutes: Double, meetsReference: Bool)
    /// Valoración general a partir de la puntuación, si existe.
    case overall(ScoreBand)
}

/// Compone el resumen del final del día con reglas transparentes.
public struct DailySummaryComposer: Sendable {
    public let configuration: HealthScoreConfiguration

    public init(configuration: HealthScoreConfiguration = HealthScoreConfiguration()) {
        self.configuration = configuration
    }

    /// Margen relativo para considerar la actividad "dentro de tu promedio".
    public static let activityTolerance = 0.15

    public func compose(day: Date, history: DailyHistory, score: DailyScore?) -> [SummaryStatement] {
        var statements: [SummaryStatement] = []

        if let score {
            statements.append(.overall(score.band))
        }

        if let steps = history.value(.steps, on: day) {
            let baseline = history.values(.steps, daysBefore: day, count: configuration.baselineDays)
            if baseline.count >= configuration.minimumBaselineDays {
                let mean = baseline.reduce(0, +) / Double(baseline.count)
                if mean > 0 {
                    let relative = (steps - mean) / mean
                    let relation: SummaryStatement.Relation = relative > Self.activityTolerance ? .above : (relative < -Self.activityTolerance ? .below : .within)
                    statements.append(.activity(relation))
                }
            }
        }

        if let resting = history.value(.restingHeartRate, on: day) {
            let baseline = history.values(.restingHeartRate, daysBefore: day, count: configuration.baselineDays)
            if baseline.count >= configuration.minimumBaselineDays {
                let stats = Statistics(baseline)
                let z = (resting - stats.mean) / max(stats.standardDeviation, 2)
                let relation: SummaryStatement.Relation = z > 1 ? .above : (z < -1 ? .below : .within)
                statements.append(.restingHeartRate(relation))
            }
        }

        if let hours = history.value(.sleepDuration, on: day) {
            statements.append(.sleep(hours: hours, withinRecommendation: configuration.recommendedSleep.contains(hours)))
        }

        let todayExercise = history.value(.exerciseTime, on: day)
        let previous = history.values(.exerciseTime, daysBefore: day, count: 6)
        if todayExercise != nil || previous.count >= 3 {
            let minutes = (todayExercise ?? 0) + previous.reduce(0, +)
            statements.append(.weeklyExercise(minutes: minutes, meetsReference: minutes >= configuration.weeklyExerciseReference))
        }

        return statements
    }
}

extension HealthDataProviding {
    /// Resumen del día con los datos del propio proveedor.
    public func dailySummary(on day: Date, calendar: Calendar, composer: DailySummaryComposer = DailySummaryComposer()) async -> [SummaryStatement] {
        let start = calendar.startOfDay(for: day)
        let days = composer.configuration.baselineDays + 1
        var series: [MetricSeries] = []
        for kind in [MetricKind.steps, .restingHeartRate, .sleepDuration, .exerciseTime] {
            series.append(await dailySeries(kind, days: days, endingOn: start))
        }
        let history = DailyHistory(series: series, calendar: calendar)
        return composer.compose(day: start, history: history, score: await dailyScore(on: start))
    }
}
