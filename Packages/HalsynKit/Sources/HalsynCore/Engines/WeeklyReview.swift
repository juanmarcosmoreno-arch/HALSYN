import Foundation

/// Indicadores del resumen semanal.
public enum WeeklyMetric: String, CaseIterable, Codable, Hashable, Sendable {
    case score
    case sleep
    case restingHeartRate
    case heartRateVariability
    case steps
    case exercise
    case running
}

/// Un dato de la semana frente a tus 4 semanas anteriores.
public struct WeeklyFact: Hashable, Sendable {
    public enum Trend: String, Hashable, Sendable {
        case up, down, similar
    }

    public let metric: WeeklyMetric
    /// Media diaria (sueño en horas, FC, HRV, pasos, puntuación) o total de la
    /// semana (minutos de ejercicio, metros corridos).
    public let value: Double
    /// El mismo cálculo en las 4 semanas anteriores (media por semana), si hay datos.
    public let baseline: Double?
    /// Carreras: número de carreras de la semana.
    public let count: Int?

    public init(metric: WeeklyMetric, value: Double, baseline: Double?, count: Int? = nil) {
        self.metric = metric
        self.value = value
        self.baseline = baseline
        self.count = count
    }

    public var change: Double? { baseline.map { value - $0 } }

    /// Diferencia mínima para decir "más" o "menos" (por debajo, "parecido").
    /// Evita leer como cambio la variación normal de una semana a otra.
    public static func threshold(_ metric: WeeklyMetric, baseline: Double) -> Double {
        switch metric {
        case .score: 5
        case .sleep: 0.25 // 15 min
        case .restingHeartRate: 2
        case .heartRateVariability, .steps, .exercise, .running: max(abs(baseline) * 0.15, 1)
        }
    }

    public var trend: Trend? {
        guard let baseline, let change else { return nil }
        if abs(change) < Self.threshold(metric, baseline: baseline) { return .similar }
        return change > 0 ? .up : .down
    }
}

/// Resumen de los últimos 7 días completos.
public struct WeeklyReview: Hashable, Sendable {
    /// Primer y último día (incluidos).
    public let start: Date
    public let end: Date
    public let facts: [WeeklyFact]

    public func fact(_ metric: WeeklyMetric) -> WeeklyFact? { facts.first { $0.metric == metric } }
}

/// Compone el resumen semanal con reglas fijas: solo métricas con datos
/// suficientes (al menos 4 de los 7 días) y comparación con las 4 semanas
/// anteriores solo si hay al menos 14 días con dato en ellas.
public enum WeeklyReviewBuilder {
    public static let days = 7
    public static let baselineWeeks = 4
    public static let minimumDays = 4
    public static let minimumBaselineDays = 14

    public static let seriesMetrics: [MetricKind] = [.sleepDuration, .restingHeartRate, .heartRateVariability, .steps, .exerciseTime]

    public static func build(history: DailyHistory, runs: [WorkoutSummary], scores: [DailyScore], endingOn lastDay: Date) -> WeeklyReview {
        let calendar = history.calendar
        let end = calendar.startOfDay(for: lastDay)
        let start = calendar.date(byAdding: .day, value: -(days - 1), to: end) ?? end
        let baselineDays = days * baselineWeeks
        // Días de la semana (incluido `end`) y de las 4 semanas anteriores.
        let afterEnd = calendar.date(byAdding: .day, value: 1, to: end) ?? end
        func week(_ kind: MetricKind) -> [Double] { history.values(kind, daysBefore: afterEnd, count: days) }
        func before(_ kind: MetricKind) -> [Double] { history.values(kind, daysBefore: start, count: baselineDays) }
        func mean(_ values: [Double]) -> Double { values.reduce(0, +) / Double(values.count) }

        var facts: [WeeklyFact] = []

        let dailyScores = scores.filter { $0.day >= start && $0.day <= end }.map { Double($0.value) }
        if dailyScores.count >= minimumDays {
            let earlier = scores.filter { $0.day < start && $0.day >= (calendar.date(byAdding: .day, value: -baselineDays, to: start) ?? start) }.map { Double($0.value) }
            facts.append(WeeklyFact(metric: .score, value: mean(dailyScores), baseline: earlier.count >= minimumBaselineDays ? mean(earlier) : nil))
        }

        let averaged: [(WeeklyMetric, MetricKind)] = [(.sleep, .sleepDuration), (.restingHeartRate, .restingHeartRate), (.heartRateVariability, .heartRateVariability), (.steps, .steps)]
        for (metric, kind) in averaged {
            let values = week(kind)
            guard values.count >= minimumDays else { continue }
            let earlier = before(kind)
            facts.append(WeeklyFact(metric: metric, value: mean(values), baseline: earlier.count >= minimumBaselineDays ? mean(earlier) : nil))
        }

        // Ejercicio: total de la semana; los días sin registro cuentan como 0.
        let exercise = week(.exerciseTime)
        if exercise.count >= minimumDays {
            let earlier = before(.exerciseTime)
            facts.append(WeeklyFact(metric: .exercise, value: exercise.reduce(0, +), baseline: earlier.count >= minimumBaselineDays ? earlier.reduce(0, +) / Double(baselineWeeks) : nil))
        }

        // Carreras: total de la semana frente a la media semanal de las 4 anteriores.
        let afterEndMoment = afterEnd
        let thisWeek = runs.filter { $0.activity.isRun && $0.start >= start && $0.start < afterEndMoment }
        let baselineStart = calendar.date(byAdding: .day, value: -baselineDays, to: start) ?? start
        let earlierRuns = runs.filter { $0.activity.isRun && $0.start >= baselineStart && $0.start < start }
        let distance = thisWeek.compactMap(\.distanceMeters).reduce(0, +)
        let earlierDistance = earlierRuns.compactMap(\.distanceMeters).reduce(0, +)
        if !thisWeek.isEmpty || !earlierRuns.isEmpty {
            facts.append(WeeklyFact(metric: .running, value: distance, baseline: earlierRuns.isEmpty ? nil : earlierDistance / Double(baselineWeeks), count: thisWeek.count))
        }

        return WeeklyReview(start: start, end: end, facts: facts)
    }
}

extension HealthDataProviding {
    /// Resumen de los 7 días completos que terminan en `lastDay`.
    public func weeklyReview(endingOn lastDay: Date, calendar: Calendar) async -> WeeklyReview {
        let end = calendar.startOfDay(for: lastDay)
        let span = WeeklyReviewBuilder.days * (WeeklyReviewBuilder.baselineWeeks + 1)
        var series: [MetricSeries] = []
        for kind in WeeklyReviewBuilder.seriesMetrics {
            series.append(await dailySeries(kind, days: span, endingOn: end))
        }
        let history = DailyHistory(series: series, calendar: calendar)
        let runs = await recentWorkouts(limit: 120)
        let scores = await dailyScores(endingOn: end, days: span)
        return WeeklyReviewBuilder.build(history: history, runs: runs, scores: scores, endingOn: end)
    }
}

/// Comprueba un texto generado por un modelo de lenguaje antes de mostrarlo.
///
/// - Cada número del texto debe aparecer en los datos que se le dieron
///   ("7,5" y "7.5" cuentan como el mismo número; también los dígitos
///   devanagari y los de ancho completo).
/// - No puede contener términos clínicos (diagnóstico, enfermedad,
///   tratamiento…) en ninguno de los idiomas de la app.
/// - Tiene que tener una longitud razonable.
///
/// Si falla, la app muestra solo los datos, sin redacción.
public enum GeneratedTextValidator {
    public enum Failure: Equatable, Sendable {
        case empty
        case tooLong
        case unknownNumber(String)
        case clinicalTerm(String)
    }

    public static let maximumLength = 900

    /// Raíces de términos clínicos (en minúsculas) que no deben aparecer.
    public static let clinicalTerms: [String] = [
        // es / pt
        "diagnóstic", "diagnostic", "enfermedad", "doença", "tratamiento", "tratamento", "medicament", "fármaco", "patolog", "arritmia", "infecci", "infecç", "trastorno", "transtorno", "síntoma", "sintoma", // nolocalize
        // en
        "diagnos", "disease", "treatment", "medication", "illness", "disorder", "arrhythmia", "infection", "symptom", // nolocalize
        // fr / it
        "maladie", "traitement", "médicament", "malattia", "trattamento", "farmac", "sintom", "symptôme", // nolocalize
        // de
        "krankheit", "behandlung", "medikament", "arznei", // nolocalize
        // sv / da
        "sjukdom", "behandling", "läkemedel", "sygdom", "medicin", // nolocalize
        // zh
        "诊断", "疾病", "治疗", "药物", "症状", // nolocalize
    ]

    public static func validate(_ text: String, allowedSources: [String]) -> Failure? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .empty }
        guard trimmed.count <= maximumLength else { return .tooLong }
        let lower = trimmed.lowercased()
        if let term = clinicalTerms.first(where: { lower.contains($0) }) {
            return .clinicalTerm(term)
        }
        let allowed = Set(allowedSources.flatMap(numbers(in:)))
        if let unknown = numbers(in: trimmed).first(where: { !allowed.contains($0) }) {
            return .unknownNumber(unknown)
        }
        return nil
    }

    /// Números del texto como secuencias de dígitos sin separadores
    /// ("7,5" → "75", "8.432" → "8432", "6:45" → "645").
    public static func numbers(in text: String) -> [String] {
        var result: [String] = []
        var current = ""
        var pendingSeparator = false
        for character in text {
            if let digit = asciiDigit(character) {
                current.append(digit)
                pendingSeparator = false
            } else if !current.isEmpty, !pendingSeparator, [",", ".", ":", "\u{202F}", "\u{00A0}", "'"].contains(character) { // nolocalize
                pendingSeparator = true
            } else {
                if !current.isEmpty { result.append(current) }
                current = ""
                pendingSeparator = false
            }
        }
        if !current.isEmpty { result.append(current) }
        return result
    }

    private static func asciiDigit(_ character: Character) -> Character? {
        guard let scalar = character.unicodeScalars.first, character.unicodeScalars.count == 1 else { return nil }
        switch scalar.value {
        case 0x30...0x39: return character
        case 0x0966...0x096F: return Character(Unicode.Scalar(scalar.value - 0x0966 + 0x30)!) // devanagari
        case 0xFF10...0xFF19: return Character(Unicode.Scalar(scalar.value - 0xFF10 + 0x30)!) // ancho completo
        default: return nil
        }
    }
}
