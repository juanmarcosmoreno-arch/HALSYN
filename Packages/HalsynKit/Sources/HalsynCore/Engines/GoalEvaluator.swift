import Foundation

/// Estado de un objetivo en un periodo.
public struct GoalProgress: Hashable, Sendable {
    public enum Pace: String, Hashable, Sendable {
        /// Ya cumplido.
        case completed
        /// Por delante de lo esperado a estas alturas del periodo.
        case ahead
        /// Dentro de lo esperado (±10 %).
        case onTrack
        /// Por detrás de lo esperado.
        case behind
        /// Periodo terminado sin cumplir.
        case missed
        /// Sin datos todavía.
        case noData
    }

    public let interval: DateInterval
    public let current: Double
    public let target: Double
    /// Días con datos en el periodo (para medias como el sueño).
    public let daysWithData: Int
    public let pace: Pace
    /// Lo que falta (0 si está cumplido).
    public let remaining: Double
    /// Lo que haría falta cada día que queda para cumplirlo (sumas), o `nil`.
    public let neededPerRemainingDay: Double?

    public var fraction: Double { target > 0 ? min(current / target, 1) : 0 }
    public var isCompleted: Bool { pace == .completed }
}

/// Resultado de un periodo pasado (para el historial y las rachas).
public struct GoalPeriodResult: Hashable, Identifiable, Sendable {
    public let interval: DateInterval
    public let value: Double
    public let target: Double
    public let hasData: Bool

    public var id: Date { interval.start }
    public var isCompleted: Bool { hasData && value >= target }
}

/// Datos que necesita el evaluador: valores diarios y carreras.
public struct GoalData: Sendable {
    public var daily: [MetricKind: [Date: Double]]
    public var runs: [WorkoutSummary]

    public init(series: [MetricSeries], runs: [WorkoutSummary], calendar: Calendar) {
        var daily: [MetricKind: [Date: Double]] = [:]
        for item in series {
            var values: [Date: Double] = [:]
            for value in item.values { values[calendar.startOfDay(for: value.day)] = value.value }
            daily[item.kind] = values
        }
        self.daily = daily
        self.runs = runs.filter { $0.activity == .outdoorRun || $0.activity == .indoorRun }
    }
}

/// Calcula el progreso de los objetivos de MÅL. Puro y probado (sin HealthKit).
///
/// - Sumas (pasos, minutos, distancia, energía, carreras): total del periodo.
/// - Medias (sueño): media de las noches con datos del periodo.
/// - Ritmo: compara lo hecho con lo esperado según la parte del periodo que ha
///   pasado (en días completos más la fracción de hoy), con ±10 % de margen.
/// - Rachas: periodos consecutivos cumplidos hacia atrás; el periodo en curso
///   suma si ya está cumplido, y no la rompe si aún no ha terminado.
public struct GoalEvaluator: Sendable {
    public let calendar: Calendar

    public init(calendar: Calendar) {
        self.calendar = calendar
    }

    public func interval(for period: Goal.Period, containing date: Date) -> DateInterval {
        let component: Calendar.Component
        switch period {
        case .daily: component = .day
        case .weekly: component = .weekOfYear
        case .monthly: component = .month
        }
        return calendar.dateInterval(of: component, for: date) ?? DateInterval(start: calendar.startOfDay(for: date), duration: 86_400)
    }

    /// Valor del objetivo en un intervalo y cuántos días tienen datos.
    public func value(_ goal: GoalDefinition, in interval: DateInterval, data: GoalData, until now: Date? = nil) -> (value: Double, daysWithData: Int) {
        let end = min(interval.end, now.map { calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: $0)) ?? $0 } ?? interval.end)
        switch goal.kind {
        case .runs, .runningDistance:
            let runs = data.runs.filter { interval.contains($0.start) && $0.start < end }
            let value = goal.kind == .runs ? Double(runs.count) : runs.compactMap(\.distanceMeters).reduce(0, +)
            return (value, Set(runs.map { calendar.startOfDay(for: $0.start) }).count)
        default:
            guard let metric = goal.kind.metric, let values = data.daily[metric] else { return (0, 0) }
            let inRange = values.filter { $0.key >= interval.start && $0.key < end }.map(\.value)
            if goal.kind.isAverage {
                return (inRange.isEmpty ? 0 : inRange.reduce(0, +) / Double(inRange.count), inRange.count)
            }
            return (inRange.reduce(0, +), inRange.count)
        }
    }

    public func progress(_ goal: GoalDefinition, data: GoalData, now: Date) -> GoalProgress {
        let interval = self.interval(for: goal.period, containing: now)
        let target = goal.target(on: now, calendar: calendar)
        let (current, days) = value(goal, in: interval, data: data, until: now)
        let remaining = max(target - current, 0)

        // Parte del periodo transcurrida (0…1).
        let elapsed = min(max(now.timeIntervalSince(interval.start) / interval.duration, 0), 1)
        let daysLeft = max(Int(ceil(interval.end.timeIntervalSince(now) / 86_400)), 0)

        let pace: GoalProgress.Pace
        if target > 0, current >= target, !(goal.kind.isAverage && days == 0) {
            pace = .completed
        } else if days == 0 && current == 0 && goal.kind.isAverage {
            pace = .noData
        } else if goal.kind.isAverage {
            pace = current >= target * 0.97 ? .onTrack : .behind
        } else {
            let expected = target * elapsed
            if current > expected * 1.1 { pace = .ahead }
            else if current >= expected * 0.9 { pace = .onTrack }
            else { pace = .behind }
        }
        let needed = goal.kind.isAverage || pace == .completed || daysLeft == 0 ? nil : remaining / Double(daysLeft)
        return GoalProgress(interval: interval, current: current, target: target, daysWithData: days, pace: pace, remaining: remaining, neededPerRemainingDay: needed)
    }

    /// Últimos `count` periodos terminados, del más antiguo al más reciente.
    public func history(_ goal: GoalDefinition, data: GoalData, now: Date, count: Int) -> [GoalPeriodResult] {
        let current = interval(for: goal.period, containing: now)
        var results: [GoalPeriodResult] = []
        var cursor = current.start
        for _ in 0..<count {
            guard let previousDay = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            let period = interval(for: goal.period, containing: previousDay)
            let (value, days) = self.value(goal, in: period, data: data)
            results.append(GoalPeriodResult(interval: period, value: value, target: goal.target(on: period.start, calendar: calendar), hasData: days > 0 || (!goal.kind.isAverage && value > 0)))
            cursor = period.start
        }
        return results.reversed()
    }

    /// Racha: periodos consecutivos cumplidos hasta hoy.
    public func streak(_ goal: GoalDefinition, data: GoalData, now: Date) -> Int {
        let currentDone = progress(goal, data: data, now: now).isCompleted
        var streak = currentDone ? 1 : 0
        for result in history(goal, data: data, now: now, count: 120).reversed() {
            guard result.isCompleted else { break }
            streak += 1
        }
        return streak
    }
}

extension HealthDataProviding {
    /// Datos para evaluar objetivos: ~13 meses de series y carreras recientes.
    public func goalData(for goals: [GoalDefinition], endingOn end: Date, calendar: Calendar) async -> GoalData {
        let metrics = Set(goals.compactMap(\.kind.metric))
        var series: [MetricSeries] = []
        for metric in metrics {
            series.append(await dailySeries(metric, days: 400, endingOn: end))
        }
        let needsRuns = goals.contains { $0.kind == .runs || $0.kind == .runningDistance }
        let runs = needsRuns ? await recentWorkouts(limit: 400) : []
        return GoalData(series: series, runs: runs, calendar: calendar)
    }
}
