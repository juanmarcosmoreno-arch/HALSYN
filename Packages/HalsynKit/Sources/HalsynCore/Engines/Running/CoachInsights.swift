import Foundation

/// Una observación sobre tu entrenamiento, con los datos que la respaldan.
/// El texto se arma en la app; aquí solo se decide si hay algo que decir.
public enum CoachInsight: Hashable, Identifiable, Sendable {
    public enum Tone: Hashable, Sendable { case positive, neutral, caution }

    /// El 5 km previsto por el modelo cambió (s; negativo = más rápido) en `weeks` semanas.
    case fiveKChanged(seconds: TimeInterval, weeks: Int)
    /// A igual ritmo, la FC cambió (lpm; negativo = más eficiente).
    case heartRateAtPace(change: Double, pace: Double)
    /// Más tiempo exigente que el recomendado (fracción de los minutos de 2 semanas).
    case tooMuchIntensity(share: Double)
    /// Kilómetros por semana frente al período anterior (cociente).
    case volumeChanged(ratio: Double, weekly: Double)
    /// FC en reposo por encima de tu línea basal (lpm).
    case restingHeartRateHigh(delta: Double)
    /// Recuperación media de 7 días frente a la de 28 (puntos).
    case recoveryTrend(delta: Double)
    /// Corres con regularidad (carreras por semana, semanas seguidas).
    case consistent(runsPerWeek: Double, weeks: Int)
    /// La estimación de la forma tiene baja confianza.
    case lowConfidence

    public var id: String { String(describing: self) }

    public var tone: Tone {
        switch self {
        case let .fiveKChanged(seconds, _): seconds < 0 ? .positive : .caution
        case let .heartRateAtPace(change, _): change < 0 ? .positive : .caution
        case .tooMuchIntensity, .restingHeartRateHigh, .lowConfidence: .caution
        case let .volumeChanged(ratio, _): ratio > 1 ? .caution : .neutral
        case let .recoveryTrend(delta): delta > 0 ? .positive : .caution
        case .consistent: .positive
        }
    }
}

/// Motor de explicaciones por reglas (sin IA). Cada regla tiene un umbral
/// mínimo para no sacar conclusiones de diferencias pequeñas:
///
/// | Observación | Regla |
/// |---|---|
/// | 5 km previsto | cambio ≥ 10 s en 4 semanas, mayor que la variación normal del modelo (±1 σ) y confianza no baja |
/// | FC a igual ritmo | cambio ≥ 3 lpm entre los últimos dos períodos de 4 semanas |
/// | Demasiada intensidad | > 30 % de los minutos con pulso de las últimas 2 semanas en esfuerzo fuerte (la referencia es ~20 %) |
/// | Volumen | km/semana de 4 semanas frente a las 4 anteriores: ≥ 1,3 o ≤ 0,6 (con ≥ 5 km/semana antes) |
/// | FC en reposo | mediana de los últimos 3 días ≥ línea basal + max(3 lpm, 1,5 × MAD) |
/// | Recuperación | media de 7 días frente a la de 28: ≥ 8 puntos de diferencia |
/// | Regularidad | 3 o más carreras en cada una de las últimas 4 semanas |
/// | Confianza baja | el modelo de rendimiento tiene confianza baja |
public enum CoachInsights {
    public static func generate(
        progress: RunnerProgress,
        performance: PerformanceAssessment?,
        restingHeartRate: [DailyValue],
        recovery: [(day: Date, value: Int?)],
        today: Date,
        calendar: Calendar
    ) -> [CoachInsight] {
        var insights: [CoachInsight] = []
        let comparison = PeriodComparison.compare(progress, weeks: 4)

        if let change = comparison.fiveKChange, abs(change) >= 10, performance?.confidence != .low,
           comparison.fiveKNoise == nil || comparison.fiveKChangeIsReal {
            insights.append(.fiveKChanged(seconds: change, weeks: 4))
        }
        if let change = comparison.heartRateChange, abs(change) >= 3, let pace = progress.referencePace {
            insights.append(.heartRateAtPace(change: change, pace: pace))
        }
        let lastTwo = progress.weeks.suffix(2)
        let hard = lastTwo.map(\.hardMinutes).reduce(0, +)
        let known = lastTwo.map { $0.easyMinutes + $0.moderateMinutes + $0.hardMinutes }.reduce(0, +)
        if known >= 60, hard / known > 0.30 {
            insights.append(.tooMuchIntensity(share: hard / known))
        }
        if comparison.previousWeeklyDistance >= 5000 {
            let ratio = comparison.weeklyDistance / comparison.previousWeeklyDistance
            if ratio >= 1.3 || ratio <= 0.6 {
                insights.append(.volumeChanged(ratio: ratio, weekly: comparison.weeklyDistance))
            }
        }
        if let delta = restingHeartRateDelta(restingHeartRate, today: today, calendar: calendar) {
            insights.append(.restingHeartRateHigh(delta: delta))
        }
        if let delta = recoveryDelta(recovery, today: today, calendar: calendar) {
            insights.append(.recoveryTrend(delta: delta))
        }
        let lastFour = progress.weeks.suffix(4)
        if lastFour.count == 4, lastFour.allSatisfy({ $0.runs >= 3 }) {
            insights.append(.consistent(runsPerWeek: Double(lastFour.map(\.runs).reduce(0, +)) / 4, weeks: 4))
        }
        if performance?.confidence == .low {
            insights.append(.lowConfidence)
        }
        // Primero lo que pide atención, luego lo positivo, luego lo neutro.
        return insights.sorted { order($0.tone) < order($1.tone) }
    }

    private static func order(_ tone: CoachInsight.Tone) -> Int {
        switch tone {
        case .caution: 0
        case .positive: 1
        case .neutral: 2
        }
    }

    static func restingHeartRateDelta(_ values: [DailyValue], today: Date, calendar: Calendar) -> Double? {
        let todayStart = calendar.startOfDay(for: today)
        guard let recentStart = calendar.date(byAdding: .day, value: -2, to: todayStart),
              let baselineStart = calendar.date(byAdding: .day, value: -30, to: recentStart) else { return nil }
        let recent = values.filter { $0.day >= recentStart && $0.day <= today }.map(\.value)
        let baseline = values.filter { $0.day >= baselineStart && $0.day < recentStart }.map(\.value)
        guard recent.count >= 2, baseline.count >= 14, let median = RacePerformanceModel.median(recent) else { return nil }
        let robust = RobustBaseline(baseline)
        let delta = median - robust.median
        return delta >= max(3, 1.5 * robust.scale) ? delta : nil
    }

    static func recoveryDelta(_ values: [(day: Date, value: Int?)], today: Date, calendar: Calendar) -> Double? {
        let todayStart = calendar.startOfDay(for: today)
        guard let weekStart = calendar.date(byAdding: .day, value: -6, to: todayStart),
              let monthStart = calendar.date(byAdding: .day, value: -27, to: todayStart) else { return nil }
        let week = values.filter { $0.day >= weekStart }.compactMap(\.value).map(Double.init)
        let month = values.filter { $0.day >= monthStart }.compactMap(\.value).map(Double.init)
        guard week.count >= 4, month.count >= 14 else { return nil }
        let delta = week.reduce(0, +) / Double(week.count) - month.reduce(0, +) / Double(month.count)
        return abs(delta) >= 8 ? delta : nil
    }
}
