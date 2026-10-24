import Foundation

extension HealthDataProviding {
    /// Calcula puntuaciones con `HealthScoreEngine` a partir de las series del
    /// propio proveedor. Lo usan tanto el modo demo como Apple Health, de modo
    /// que ambos siguen exactamente las mismas reglas.
    ///
    /// La variación semanal compara cada día con la media de los 7 días
    /// anteriores que tengan puntuación (al menos 3).
    public func computeDailyScores(
        endingOn end: Date,
        days: Int,
        engine: HealthScoreEngine? = nil,
        calendar: Calendar,
        origin: DataOrigin
    ) async -> [DailyScore] {
        guard days > 0 else { return [] }
        var resolvedEngine = engine
        if resolvedEngine == nil {
            resolvedEngine = HealthScoreEngine(configuration: .forAge(await profileAge(on: end, calendar: calendar)))
        }
        let engine = resolvedEngine ?? HealthScoreEngine()
        let lastDay = calendar.startOfDay(for: end)
        let evaluatedDays = days + 7
        let fetchDays = evaluatedDays + engine.historyDaysNeeded

        var series: [MetricSeries] = []
        for kind in HealthScoreEngine.inputs {
            series.append(await dailySeries(kind, days: fetchDays, endingOn: lastDay))
        }
        let history = DailyHistory(series: series, calendar: calendar)

        var results: [Date: HealthScoreEngine.Result] = [:]
        var ordered: [Date] = []
        for offset in stride(from: evaluatedDays - 1, through: 0, by: -1) {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: lastDay) else { continue }
            results[day] = engine.evaluate(day: day, history: history)
            ordered.append(day)
        }

        return ordered.suffix(days).compactMap { day -> DailyScore? in
            guard let result = results[day], let value = result.score else { return nil }
            let previous = (1...7).compactMap { offset in
                calendar.date(byAdding: .day, value: -offset, to: day).flatMap { results[$0]?.score }
            }
            let change = previous.count >= 3
                ? Int((Double(value) - Double(previous.reduce(0, +)) / Double(previous.count)).rounded())
                : nil
            return DailyScore(day: day, value: value, weeklyChange: change, origin: origin, breakdown: result.breakdown)
        }
    }

    /// Edad para las referencias: la del perfil de la app o, si no, la de Salud.
    public func profileAge(on day: Date, calendar: Calendar) async -> Int? {
        var birthDate = ProfileDefaults.birthDate()
        if birthDate == nil { birthDate = await userCharacteristics().birthDate }
        return birthDate.flatMap { ReferencePercentileEngine.age(birthDate: $0, on: day, calendar: calendar) }
    }
}

/// Datos del perfil que la app guarda en `UserDefaults` y usan los motores.
public enum ProfileDefaults {
    public static let birthDateKey = "halsyn.profile.birthDate"

    public static func birthDate(_ defaults: UserDefaults = .standard) -> Date? {
        (defaults.object(forKey: birthDateKey) as? Double).map(Date.init(timeIntervalSinceReferenceDate:))
    }
}
