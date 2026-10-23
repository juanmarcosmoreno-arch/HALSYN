import Foundation

// MARK: - Modelos

/// Qué dirección es favorable para una métrica (para el tono del texto, nunca para un diagnóstico).
public enum FavorableDirection: Sendable {
    case higher
    case lower
    /// Mejor dentro de un rango (sueño 7–9 h).
    case within(ClosedRange<Double>)
    /// Sin dirección preferida.
    case neutral
}

/// Cambio de una métrica entre las 4 semanas anteriores y las 4 últimas.
public struct TrendInsight: Hashable, Identifiable, Sendable {
    public let metric: MetricKind
    public let previousMean: Double
    public let recentMean: Double
    public let previousCount: Int
    public let recentCount: Int
    public let pValue: Double
    public let qValue: Double
    public let effectSize: Double
    /// `true` favorable, `false` desfavorable, `nil` neutro.
    public let isFavorable: Bool?
    /// Serie de las 8 semanas para el gráfico.
    public let values: [DailyValue]
    public let splitDay: Date

    public var id: MetricKind { metric }
    public var difference: Double { recentMean - previousMean }
}

/// Relación observada entre dos métricas en días emparejados (no implica causa).
public struct RelationshipInsight: Hashable, Identifiable, Sendable {
    public let candidate: RelationshipCandidate
    public let pairs: Int
    public let rho: Double
    public let pValue: Double
    public let qValue: Double
    /// Umbral (mediana del predictor) que separa los dos grupos.
    public let threshold: Double
    public let lowGroupMean: Double
    public let highGroupMean: Double
    public let lowGroupCount: Int
    public let highGroupCount: Int

    public var id: String { candidate.id }
}

/// Par predictor → resultado con desfase en días, elegido por plausibilidad fisiológica.
public struct RelationshipCandidate: Hashable, Identifiable, Sendable {
    public let predictor: MetricKind
    public let outcome: MetricKind
    /// El resultado se mira `lag` días después del predictor.
    public let lag: Int

    public var id: String { "\(predictor.rawValue)→\(outcome.rawValue)+\(lag)" }

    /// Lista cerrada: no se buscan correlaciones entre todo con todo.
    public static let curated: [RelationshipCandidate] = [
        // Sueño de la noche que termina el día D → HRV y FC en reposo del día D.
        RelationshipCandidate(predictor: .sleepDuration, outcome: .heartRateVariability, lag: 0),
        RelationshipCandidate(predictor: .sleepDuration, outcome: .restingHeartRate, lag: 0),
        // Ejercicio del día D → HRV, FC en reposo del día siguiente y sueño de esa noche.
        RelationshipCandidate(predictor: .exerciseTime, outcome: .heartRateVariability, lag: 1),
        RelationshipCandidate(predictor: .exerciseTime, outcome: .restingHeartRate, lag: 1),
        RelationshipCandidate(predictor: .exerciseTime, outcome: .sleepDuration, lag: 1),
        // Pasos del día D → sueño de la noche siguiente.
        RelationshipCandidate(predictor: .steps, outcome: .sleepDuration, lag: 1),
        // Luz natural del día D → sueño de esa noche (se guarda en D+1).
        RelationshipCandidate(predictor: .timeInDaylight, outcome: .sleepDuration, lag: 1),
    ]
}

/// Diferencia sistemática entre días de la semana.
public struct WeekdayInsight: Hashable, Identifiable, Sendable {
    public let metric: MetricKind
    /// Media por día de la semana (1 = domingo … 7 = sábado, `Calendar.weekday`).
    public let means: [Int: Double]
    public let counts: [Int: Int]
    public let pValue: Double
    public let highest: Int
    public let lowest: Int

    public var id: MetricKind { metric }
}

/// Récord personal con su fecha.
public struct PersonalRecord: Hashable, Identifiable, Sendable {
    public enum Kind: String, Hashable, Sendable {
        case mostSteps
        case longestRun
        case fastestRun
        case highestVO2Max
        case lowestWeeklyRestingHeartRate
    }

    public let kind: Kind
    public let value: Double
    public let date: Date
    public let origin: DataOrigin

    public var id: Kind { kind }
}

/// Análisis que aún no se puede hacer y cuántos datos faltan.
public struct InsightRequirement: Hashable, Identifiable, Sendable {
    public enum Analysis: String, Hashable, Sendable {
        case trends
        case relationships
        case weekdays
    }

    public let analysis: Analysis
    public let metric: MetricKind?
    public let have: Int
    public let need: Int

    public var id: String { "\(analysis.rawValue)-\(metric?.rawValue ?? "")" }
    public var progress: Double { need > 0 ? min(Double(have) / Double(need), 1) : 1 }
}

public struct InsightReport: Hashable, Sendable {
    public var trends: [TrendInsight] = []
    public var relationships: [RelationshipInsight] = []
    public var weekdays: [WeekdayInsight] = []
    public var records: [PersonalRecord] = []
    public var requirements: [InsightRequirement] = []
    public var origin: DataOrigin?

    public init() {}

    public var isEmpty: Bool { trends.isEmpty && relationships.isEmpty && weekdays.isEmpty && records.isEmpty }
}

// MARK: - Motor

/// Motor de INSIKT. Reglas (Documentation/INSIGHTS.md):
/// - Solo se muestra una observación si supera requisitos mínimos de datos,
///   un contraste estadístico con corrección por comparaciones múltiples
///   (Benjamini–Hochberg, q < 0,05) y un tamaño de efecto mínimo.
/// - Las relaciones se buscan solo en una lista cerrada de pares plausibles
///   y se describen como observaciones, nunca como causas.
public struct InsightEngine: Sendable {
    public static let version = "0.1"

    public struct Configuration: Sendable {
        public var windowDays = 28
        public var minimumPerWindow = 14
        public var minimumTrendEffect = 0.4
        public var minimumPairs = 21
        public var minimumGroup = 7
        public var minimumCorrelation = 0.25
        public var weekdayWeeks = 12
        public var minimumPerWeekday = 4
        public var minimumWeekdayEffect = 0.5
        public var falseDiscoveryRate = 0.05

        public init() {}
    }

    public static let trendMetrics: [MetricKind] = [.restingHeartRate, .heartRateVariability, .vo2Max, .sleepDuration, .steps, .exerciseTime]
    public static let weekdayMetrics: [MetricKind] = [.steps, .exerciseTime, .sleepDuration]
    public static let inputs: [MetricKind] = [.restingHeartRate, .heartRateVariability, .vo2Max, .sleepDuration, .steps, .exerciseTime, .timeInDaylight]

    public let configuration: Configuration

    public init(configuration: Configuration = Configuration()) {
        self.configuration = configuration
    }

    public static func favorableDirection(_ metric: MetricKind) -> FavorableDirection {
        switch metric {
        case .restingHeartRate: .lower
        case .heartRateVariability, .vo2Max, .steps, .exerciseTime, .walkingRunningDistance, .activeEnergy, .timeInDaylight: .higher
        case .sleepDuration: .within(7...9)
        default: .neutral
        }
    }

    public func analyze(history: DailyHistory, endingOn end: Date, workouts: [WorkoutSummary], origin: DataOrigin) -> InsightReport {
        let calendar = history.calendar
        let last = calendar.startOfDay(for: end)
        var report = InsightReport()
        report.origin = origin

        // Tendencias: últimas 4 semanas frente a las 4 anteriores.
        var trendCandidates: [(TrendInsight, Stats.WelchResult)] = []
        for metric in Self.trendMetrics {
            let recent = window(metric, history: history, endingOn: last, days: configuration.windowDays)
            let previousEnd = calendar.date(byAdding: .day, value: -configuration.windowDays, to: last) ?? last
            let previous = window(metric, history: history, endingOn: previousEnd, days: configuration.windowDays)
            guard recent.count >= configuration.minimumPerWindow, previous.count >= configuration.minimumPerWindow else {
                report.requirements.append(InsightRequirement(analysis: .trends, metric: metric, have: min(recent.count, previous.count), need: configuration.minimumPerWindow))
                continue
            }
            guard let test = Stats.welch(previous.map(\.value), recent.map(\.value)),
                  let recentMean = Stats.mean(recent.map(\.value)), let previousMean = Stats.mean(previous.map(\.value)) else { continue }
            let splitDay = calendar.date(byAdding: .day, value: 1, to: previousEnd) ?? previousEnd
            let insight = TrendInsight(
                metric: metric, previousMean: previousMean, recentMean: recentMean,
                previousCount: previous.count, recentCount: recent.count,
                pValue: test.pValue, qValue: 1, effectSize: test.effectSize,
                isFavorable: Self.isFavorable(metric, from: previousMean, to: recentMean),
                values: previous + recent, splitDay: splitDay
            )
            trendCandidates.append((insight, test))
        }
        let trendQ = Stats.benjaminiHochberg(trendCandidates.map(\.1.pValue))
        for (index, candidate) in trendCandidates.enumerated() where trendQ[index] < configuration.falseDiscoveryRate && abs(candidate.1.effectSize) >= configuration.minimumTrendEffect {
            let t = candidate.0
            report.trends.append(TrendInsight(metric: t.metric, previousMean: t.previousMean, recentMean: t.recentMean, previousCount: t.previousCount, recentCount: t.recentCount, pValue: t.pValue, qValue: trendQ[index], effectSize: t.effectSize, isFavorable: t.isFavorable, values: t.values, splitDay: t.splitDay))
        }
        report.trends.sort { abs($0.effectSize) > abs($1.effectSize) }

        // Relaciones entre métricas (lista cerrada).
        var relationshipCandidates: [RelationshipInsight] = []
        var maxPairs = 0
        for candidate in RelationshipCandidate.curated {
            let pairs = pairedValues(candidate, history: history, endingOn: last, days: 180)
            maxPairs = max(maxPairs, pairs.count)
            guard pairs.count >= configuration.minimumPairs,
                  let rho = Stats.spearman(pairs.map(\.0), pairs.map(\.1)),
                  let p = Stats.correlationPValue(rho, n: pairs.count),
                  let threshold = Stats.median(pairs.map(\.0)) else { continue }
            let low = pairs.filter { $0.0 < threshold }.map(\.1)
            let high = pairs.filter { $0.0 >= threshold }.map(\.1)
            guard low.count >= configuration.minimumGroup, high.count >= configuration.minimumGroup,
                  let lowMean = Stats.mean(low), let highMean = Stats.mean(high) else { continue }
            relationshipCandidates.append(RelationshipInsight(candidate: candidate, pairs: pairs.count, rho: rho, pValue: p, qValue: 1, threshold: threshold, lowGroupMean: lowMean, highGroupMean: highMean, lowGroupCount: low.count, highGroupCount: high.count))
        }
        if maxPairs < configuration.minimumPairs {
            report.requirements.append(InsightRequirement(analysis: .relationships, metric: nil, have: maxPairs, need: configuration.minimumPairs))
        }
        // La corrección cuenta todos los pares de la lista, también los no evaluables (conservador).
        let relationshipP = relationshipCandidates.map(\.pValue) + Array(repeating: 1.0, count: RelationshipCandidate.curated.count - relationshipCandidates.count)
        let relationshipQ = Stats.benjaminiHochberg(relationshipP)
        for (index, insight) in relationshipCandidates.enumerated() where relationshipQ[index] < configuration.falseDiscoveryRate && abs(insight.rho) >= configuration.minimumCorrelation {
            report.relationships.append(RelationshipInsight(candidate: insight.candidate, pairs: insight.pairs, rho: insight.rho, pValue: insight.pValue, qValue: relationshipQ[index], threshold: insight.threshold, lowGroupMean: insight.lowGroupMean, highGroupMean: insight.highGroupMean, lowGroupCount: insight.lowGroupCount, highGroupCount: insight.highGroupCount))
        }
        report.relationships.sort { abs($0.rho) > abs($1.rho) }

        // Semana tipo.
        var weekdayCandidates: [WeekdayInsight] = []
        for metric in Self.weekdayMetrics {
            let values = window(metric, history: history, endingOn: last, days: configuration.weekdayWeeks * 7)
            var groups: [Int: [Double]] = [:]
            for value in values {
                groups[calendar.component(.weekday, from: value.day), default: []].append(value.value)
            }
            let fewest = (1...7).map { groups[$0]?.count ?? 0 }.min() ?? 0
            guard fewest >= configuration.minimumPerWeekday else {
                report.requirements.append(InsightRequirement(analysis: .weekdays, metric: metric, have: fewest, need: configuration.minimumPerWeekday))
                continue
            }
            guard let anova = Stats.oneWayANOVA((1...7).map { groups[$0] ?? [] }),
                  let overallSD = Stats.standardDeviation(values.map(\.value)), overallSD > 0 else { continue }
            let means = groups.compactMapValues { Stats.mean($0) }
            guard let highest = means.max(by: { $0.value < $1.value }), let lowest = means.min(by: { $0.value < $1.value }),
                  (highest.value - lowest.value) / overallSD >= configuration.minimumWeekdayEffect else { continue }
            weekdayCandidates.append(WeekdayInsight(metric: metric, means: means, counts: groups.mapValues(\.count), pValue: anova.pValue, highest: highest.key, lowest: lowest.key))
        }
        let weekdayQ = Stats.benjaminiHochberg(weekdayCandidates.map(\.pValue))
        report.weekdays = weekdayCandidates.enumerated().filter { weekdayQ[$0.offset] < configuration.falseDiscoveryRate }.map(\.element)

        report.records = records(history: history, endingOn: last, workouts: workouts, origin: origin)
        return report
    }

    // MARK: Récords

    func records(history: DailyHistory, endingOn last: Date, workouts: [WorkoutSummary], origin: DataOrigin) -> [PersonalRecord] {
        var result: [PersonalRecord] = []
        let days = window(.steps, history: history, endingOn: last, days: 365)
        if let best = days.max(by: { $0.value < $1.value }) {
            result.append(PersonalRecord(kind: .mostSteps, value: best.value, date: best.day, origin: origin))
        }
        let vo2 = window(.vo2Max, history: history, endingOn: last, days: 365)
        if let best = vo2.max(by: { $0.value < $1.value }) {
            result.append(PersonalRecord(kind: .highestVO2Max, value: best.value, date: best.day, origin: origin))
        }
        // FC en reposo: mejor media de 7 días con al menos 5 valores (un día suelto no es récord).
        let rhr = window(.restingHeartRate, history: history, endingOn: last, days: 365)
        var bestWeek: (Double, Date)?
        for (index, value) in rhr.enumerated() where index >= 4 {
            let start = history.calendar.date(byAdding: .day, value: -6, to: value.day) ?? value.day
            let week = rhr.filter { $0.day >= start && $0.day <= value.day }.map(\.value)
            if week.count >= 5, let average = Stats.mean(week), average < (bestWeek?.0 ?? .infinity) {
                bestWeek = (average, value.day)
            }
        }
        if let bestWeek {
            result.append(PersonalRecord(kind: .lowestWeeklyRestingHeartRate, value: bestWeek.0, date: bestWeek.1, origin: origin))
        }
        let runs = workouts.filter { $0.activity == .outdoorRun || $0.activity == .indoorRun }
        if let longest = runs.filter({ ($0.distanceMeters ?? 0) > 0 }).max(by: { ($0.distanceMeters ?? 0) < ($1.distanceMeters ?? 0) }), let distance = longest.distanceMeters {
            result.append(PersonalRecord(kind: .longestRun, value: distance, date: longest.start, origin: longest.origin))
        }
        // Ritmo más rápido en carreras de al menos 3 km (las cortas no son comparables).
        if let fastest = runs.filter({ ($0.distanceMeters ?? 0) >= 3000 }).compactMap({ run in run.averagePace.map { (run, $0) } }).min(by: { $0.1 < $1.1 }) {
            result.append(PersonalRecord(kind: .fastestRun, value: fastest.1.secondsPerKilometer, date: fastest.0.start, origin: fastest.0.origin))
        }
        return result
    }

    // MARK: Utilidades

    static func isFavorable(_ metric: MetricKind, from before: Double, to after: Double) -> Bool? {
        switch favorableDirection(metric) {
        case .higher: return after > before
        case .lower: return after < before
        case let .within(range):
            func distance(_ value: Double) -> Double { range.contains(value) ? 0 : min(abs(value - range.lowerBound), abs(value - range.upperBound)) }
            let a = distance(before), b = distance(after)
            return a == b ? nil : b < a
        case .neutral: return nil
        }
    }

    /// Valores existentes en los `days` días que terminan en `end` (incluido), en orden.
    func window(_ metric: MetricKind, history: DailyHistory, endingOn end: Date, days: Int) -> [DailyValue] {
        (0..<days).reversed().compactMap { offset in
            history.calendar.date(byAdding: .day, value: -offset, to: end).flatMap { day in
                history.value(metric, on: day).map { DailyValue(day: day, value: $0) }
            }
        }
    }

    func pairedValues(_ candidate: RelationshipCandidate, history: DailyHistory, endingOn end: Date, days: Int) -> [(Double, Double)] {
        (candidate.lag..<days).compactMap { offset in
            guard let outcomeDay = history.calendar.date(byAdding: .day, value: -(offset - candidate.lag), to: end),
                  let predictorDay = history.calendar.date(byAdding: .day, value: -candidate.lag, to: outcomeDay),
                  let x = history.value(candidate.predictor, on: predictorDay),
                  let y = history.value(candidate.outcome, on: outcomeDay) else { return nil }
            return (x, y)
        }
    }
}

extension HealthDataProviding {
    /// Informe de INSIKT con 180 días de historia (365 para récords).
    public func computeInsights(endingOn end: Date, calendar: Calendar, origin: DataOrigin, engine: InsightEngine = InsightEngine()) async -> InsightReport {
        let last = calendar.startOfDay(for: end)
        var series: [MetricSeries] = []
        for kind in InsightEngine.inputs {
            series.append(await dailySeries(kind, days: kind == .steps || kind == .vo2Max || kind == .restingHeartRate ? 365 : 180, endingOn: last))
        }
        let workouts = await recentWorkouts(limit: 300)
        return engine.analyze(history: DailyHistory(series: series, calendar: calendar), endingOn: last, workouts: workouts, origin: origin)
    }
}
